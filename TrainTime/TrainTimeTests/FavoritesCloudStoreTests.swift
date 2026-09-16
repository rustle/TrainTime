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
                    at date: Date) -> FavoriteRecord {
    FavoriteRecord(code: code,
                   isFavorite: isFavorite,
                   updatedAt: date)
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
}
