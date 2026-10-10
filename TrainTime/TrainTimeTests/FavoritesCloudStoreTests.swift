import Foundation
import GRDB
import Synchronization
import Testing
@testable import TrainTime

// MARK: - Doubles

/// In-memory stand-in for iCloud key-value storage that the test can drive.
private final class TestCloudStorage: FavoritesCloudStorage, Sendable {
    private struct State {
        var data: Data?
        var setCount = 0
        var continuation: AsyncStream<FavoritesCloudChangeReason>.Continuation?
    }
    private let state = Mutex(State())
    func data(forKey key: String) -> Data? {
        state.withLock { $0.data }
    }
    func set(_ data: Data?,
             forKey key: String) {
        state.withLock {
            $0.data = data
            $0.setCount += 1
        }
    }
    func synchronize() {}
    func externalChanges() -> AsyncStream<FavoritesCloudChangeReason> {
        let (stream, continuation) = AsyncStream<FavoritesCloudChangeReason>.makeStream()
        state.withLock { $0.continuation = continuation }
        return stream
    }
    /// Simulates another device, or the account, changing the cloud value.
    func replace(with records: [FavoriteRecord]?,
                 reason: FavoritesCloudChangeReason) throws {
        let data = try records.map { try JSONEncoder().encode($0) }
        state.withLock { $0.data = data }
        state.withLock { $0.continuation }?.yield(reason)
    }
    var records: [FavoriteRecord] {
        get throws {
            guard let data = state.withLock({ $0.data }) else {
                return []
            }
            return try JSONDecoder().decode([FavoriteRecord].self,
                                            from: data)
        }
    }
    var setCount: Int {
        state.withLock { $0.setCount }
    }
}

private final class TestClock: Sendable {
    private let date: Mutex<Date>
    init(_ date: Date) {
        self.date = Mutex(date)
    }
    func now() -> Date {
        date.withLock { $0 }
    }
    func advance(by interval: TimeInterval) {
        date.withLock { $0 += interval }
    }
}

// MARK: - Harness

private struct Harness {
    let database: TestDatabase
    let storage = TestCloudStorage()
    let clock = TestClock(iso8601("2026-09-15T12:00:00Z"))
    let store: FavoritesCloudStore
    init() async throws {
        database = try TestDatabase.make()
        try await database.runMigrations()
        let clock = clock
        store = FavoritesCloudStore(userDataConnection: database.userDataConnection,
                                    storage: storage,
                                    now: { clock.now() })
    }
    func tearDown() {
        try? database.closeAndDelete()
    }
    /// A favorite written before the app stamped rows, as an upgrading user has.
    func writeLegacyFavorite(_ code: String) async throws {
        try await database.userDataConnection
            .writeUserDataForStation(code: code,
                                     isFavorite: true)
    }
    func localFavorites() async throws -> Set<String> {
        try await database.userDataConnection.read { db in
            Set(try StationUserData
                .filter(StationUserData.Columns.isFavorite == true)
                .select(StationUserData.Columns.code, as: String.self)
                .fetchAll(db))
        }
    }
    func cloudFavorites() throws -> Set<String> {
        Set(try storage.records.filter(\.isFavorite).map(\.code))
    }
    /// Favorites in the order the list would show them.
    func localFavoriteOrder() async throws -> [String] {
        let positions = try await database.userDataConnection.read { db in
            try StationUserData
                .filter(StationUserData.Columns.isFavorite == true)
                .order(StationUserData.Columns.code)
                .fetchAll(db)
                .map { FavoritePosition(code: $0.code,
                                        sortOrder: $0.sortOrder) }
        }
        return FavoritesOrdering.displayOrder(positions).map(\.code)
    }
    func cloudSortOrder(of code: String) throws -> Double? {
        try storage.records.first { $0.code == code }?.sortOrder
    }
    /// External changes are handled on the store's own task, so poll.
    func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if try await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try await condition()
    }
}

private func record(_ code: String,
                    isFavorite: Bool,
                    at date: Date,
                    sortOrder: Double? = nil) -> FavoriteRecord {
    FavoriteRecord(code: code,
                   isFavorite: isFavorite,
                   updatedAt: date,
                   sortOrder: sortOrder)
}

private func change(_ code: String,
                    sortOrder: Double?) -> StationUserDataChange {
    StationUserDataChange(code: code,
                          isFavorite: true,
                          sortOrder: sortOrder)
}

// MARK: - Tests

struct FavoritesCloudStoreTests {
    @Test func firstContactKeepsBothSidesFavorites() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        try await harness.writeLegacyFavorite("UCA")
        try harness.storage.replace(with: [record("ROC",
                                                  isFavorite: true,
                                                  at: iso8601("2026-09-01T12:00:00Z"))],
                                    reason: .initialSync)

        await harness.store.start()

        #expect(try await harness.localFavorites() == ["UCA", "ROC"])
        #expect(try harness.cloudFavorites() == ["UCA", "ROC"])
    }
    @Test func emptyCloudDoesNotWipeLocalFavorites() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        try await harness.writeLegacyFavorite("UCA")

        await harness.store.start()

        #expect(try await harness.localFavorites() == ["UCA"])
        #expect(try harness.cloudFavorites() == ["UCA"])
    }
    @Test func newerCloudUnfavoriteWins() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserDataForStation(code: "UCA",
                                                        isFavorite: true)
        #expect(try harness.cloudFavorites() == ["UCA"])

        // Another device unfavorites it a minute later.
        harness.clock.advance(by: 60)
        try harness.storage.replace(with: [record("UCA",
                                                  isFavorite: false,
                                                  at: harness.clock.now())],
                                    reason: .serverChange)

        #expect(try await harness.waitUntil {
            try await harness.localFavorites().isEmpty
        })
    }
    @Test func olderCloudUnfavoriteLoses() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserDataForStation(code: "UCA",
                                                        isFavorite: true)

        // A stale unfavorite from before the local favorite arrives late.
        try harness.storage.replace(with: [record("UCA",
                                                  isFavorite: false,
                                                  at: harness.clock.now() - 60)],
                                    reason: .serverChange)

        // The local favorite stands and is pushed back over the stale value.
        #expect(try await harness.waitUntil {
            try harness.cloudFavorites() == ["UCA"]
        })
        #expect(try await harness.localFavorites() == ["UCA"])
    }
    @Test func localUnfavoriteTravelsToTheCloud() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserDataForStation(code: "UCA",
                                                        isFavorite: true)
        harness.clock.advance(by: 1)
        try await harness.store.writeUserDataForStation(code: "UCA",
                                                        isFavorite: nil)

        let records = try harness.storage.records
        #expect(records.map(\.code) == ["UCA"])
        #expect(records.first?.isFavorite == false)
        #expect(try await harness.localFavorites().isEmpty)
    }
    @Test func accountChangeWithNoCloudValueKeepsLocalFavorites() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserDataForStation(code: "UCA",
                                                        isFavorite: true)

        // The new account has never used the app.
        try harness.storage.replace(with: nil,
                                    reason: .accountChange)

        #expect(try await harness.waitUntil {
            try harness.cloudFavorites() == ["UCA"]
        })
        #expect(try await harness.localFavorites() == ["UCA"])
    }
    @Test func quotaViolationTakesTheServerValueWithoutPushing() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        try await harness.writeLegacyFavorite("UCA")
        await harness.store.start()
        let pushesBefore = harness.storage.setCount

        try harness.storage.replace(with: [record("ROC",
                                                  isFavorite: true,
                                                  at: harness.clock.now())],
                                    reason: .quotaViolation)

        #expect(try await harness.waitUntil {
            try await harness.localFavorites() == ["UCA", "ROC"]
        })
        #expect(harness.storage.setCount == pushesBefore)
    }
    // MARK: Ordering
    @Test func reorderTravelsToTheCloudAsOneWrite() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserData([change("UCA", sortOrder: 0),
                                               change("ROC", sortOrder: 1)])
        let pushesBefore = harness.storage.setCount

        harness.clock.advance(by: 1)
        try await harness.store.writeUserData([change("ROC", sortOrder: -1)])

        #expect(harness.storage.setCount == pushesBefore + 1)
        #expect(try harness.cloudSortOrder(of: "ROC") == -1)
        #expect(try harness.cloudSortOrder(of: "UCA") == 0)
        #expect(try await harness.localFavoriteOrder() == ["ROC", "UCA"])
    }
    @Test func cloudReorderIsAppliedLocally() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserData([change("UCA", sortOrder: 0),
                                               change("ROC", sortOrder: 1)])

        // Another device drags ROC to the top.
        harness.clock.advance(by: 60)
        try harness.storage.replace(with: [record("UCA", isFavorite: true, at: harness.clock.now() - 60, sortOrder: 0),
                                           record("ROC", isFavorite: true, at: harness.clock.now(), sortOrder: -1)],
                                    reason: .serverChange)

        #expect(try await harness.waitUntil {
            try await harness.localFavoriteOrder() == ["ROC", "UCA"]
        })
    }
    @Test func unfavoritingClearsThePositionEverywhere() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        await harness.store.start()
        try await harness.store.writeUserData([change("UCA", sortOrder: 0)])
        harness.clock.advance(by: 1)

        try await harness.store.writeUserData([StationUserDataChange(code: "UCA",
                                                                     isFavorite: nil,
                                                                     sortOrder: nil)])

        #expect(try harness.cloudSortOrder(of: "UCA") == nil)
        let local = try await harness.database.userDataConnection.read { db in
            try StationUserData.fetchOne(db, key: "UCA")
        }
        #expect(local?.isFavorite == nil)
        #expect(local?.sortOrder == nil)
    }
    @Test func legacyFavoritesReachTheCloudWithoutAPosition() async throws {
        let harness = try await Harness()
        defer { harness.tearDown() }
        try await harness.writeLegacyFavorite("UCA")

        await harness.store.start()

        #expect(try harness.cloudFavorites() == ["UCA"])
        #expect(try harness.cloudSortOrder(of: "UCA") == nil)
    }
}

struct FavoriteRecordCodingTests {
    @Test func payloadFromBeforeOrderingStillDecodes() throws {
        let json = Data("""
        [{"code":"UCA","isFavorite":true,"updatedAt":780321600}]
        """.utf8)
        let records = try JSONDecoder().decode([FavoriteRecord].self,
                                               from: json)
        #expect(records == [FavoriteRecord(code: "UCA",
                                           isFavorite: true,
                                           updatedAt: Date(timeIntervalSinceReferenceDate: 780321600))])
        #expect(records.first?.sortOrder == nil)
    }
    @Test func missingOrderIsLeftOutOfThePayload() throws {
        let data = try JSONEncoder().encode([FavoriteRecord(code: "UCA",
                                                            isFavorite: true,
                                                            updatedAt: Date(timeIntervalSinceReferenceDate: 0))])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("sortOrder"))
    }
    @Test func orderRoundTrips() throws {
        let record = FavoriteRecord(code: "UCA",
                                    isFavorite: true,
                                    updatedAt: Date(timeIntervalSinceReferenceDate: 0),
                                    sortOrder: 2.5)
        let data = try JSONEncoder().encode([record])
        #expect(try JSONDecoder().decode([FavoriteRecord].self, from: data) == [record])
    }
}

struct FavoriteRecordMergeTests {
    @Test func laterRecordWinsPerStation() {
        let older = iso8601("2026-09-01T12:00:00Z")
        let newer = iso8601("2026-09-02T12:00:00Z")
        let merged = [record("UCA", isFavorite: true, at: older),
                      record("ROC", isFavorite: true, at: newer)]
            .merged(with: [record("UCA", isFavorite: false, at: newer),
                           record("ROC", isFavorite: false, at: older),
                           record("SYR", isFavorite: true, at: older)])
        #expect(merged == [record("ROC", isFavorite: true, at: newer),
                           record("SYR", isFavorite: true, at: older),
                           record("UCA", isFavorite: false, at: newer)])
    }
    @Test func tieKeepsTheFavorite() {
        let date = iso8601("2026-09-01T12:00:00Z")
        let merged = [record("UCA", isFavorite: false, at: date)]
            .merged(with: [record("UCA", isFavorite: true, at: date)])
        #expect(merged == [record("UCA", isFavorite: true, at: date)])
    }
    @Test func laterMoveWinsOverAnEarlierOne() {
        let older = iso8601("2026-09-01T12:00:00Z")
        let newer = iso8601("2026-09-02T12:00:00Z")
        let merged = [record("UCA", isFavorite: true, at: older, sortOrder: 0)]
            .merged(with: [record("UCA", isFavorite: true, at: newer, sortOrder: 5)])
        #expect(merged == [record("UCA", isFavorite: true, at: newer, sortOrder: 5)])
    }
    @Test func favoriteFromAnOlderAppVersionKeepsThePositionItDidNotKnowAbout() {
        let older = iso8601("2026-09-01T12:00:00Z")
        let newer = iso8601("2026-09-02T12:00:00Z")
        let merged = [record("UCA", isFavorite: true, at: older, sortOrder: 3)]
            .merged(with: [record("UCA", isFavorite: true, at: newer)])
        #expect(merged == [record("UCA", isFavorite: true, at: newer, sortOrder: 3)])
    }
    @Test func newerUnfavoriteDropsThePosition() {
        let older = iso8601("2026-09-01T12:00:00Z")
        let newer = iso8601("2026-09-02T12:00:00Z")
        let merged = [record("UCA", isFavorite: true, at: older, sortOrder: 3)]
            .merged(with: [record("UCA", isFavorite: false, at: newer)])
        #expect(merged == [record("UCA", isFavorite: false, at: newer)])
    }
    @Test func mergeDoesNotDependOnWhichSideComesFirst() {
        let date = iso8601("2026-09-01T12:00:00Z")
        let cases: [([FavoriteRecord], [FavoriteRecord])] = [
            ([record("UCA", isFavorite: true, at: date, sortOrder: 1)],
             [record("UCA", isFavorite: true, at: date, sortOrder: 2)]),
            ([record("UCA", isFavorite: true, at: date)],
             [record("UCA", isFavorite: true, at: date, sortOrder: 2)]),
            ([record("UCA", isFavorite: false, at: date)],
             [record("UCA", isFavorite: true, at: date, sortOrder: 2)]),
        ]
        for (lhs, rhs) in cases {
            #expect(lhs.merged(with: rhs) == rhs.merged(with: lhs))
        }
        #expect([record("UCA", isFavorite: true, at: date, sortOrder: 1)]
            .merged(with: [record("UCA", isFavorite: true, at: date, sortOrder: 2)])
            == [record("UCA", isFavorite: true, at: date, sortOrder: 1)])
    }
}
