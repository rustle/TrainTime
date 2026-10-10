import Amtrak
import Foundation
import Testing
@testable import TrainTime

// MARK: - Doubles

/// Hands out one stations stream and lets the test drive it.
private actor TestStationsStreamProvider: StationsStreamProvider {
    private var continuations: [AsyncThrowingStream<[TrainTime.Station], any Error>.Continuation] = []
    func stations() async throws -> any AsyncThrowingSendableSequence<[TrainTime.Station]> {
        let (stream, continuation) = AsyncThrowingStream<[TrainTime.Station], any Error>.makeStream()
        continuations.append(continuation)
        return stream
    }
    func yield(_ stations: [TrainTime.Station]) {
        for continuation in continuations {
            continuation.yield(stations)
        }
    }
}

private actor RecordingUserDataProvider: WriteUserDataForStationProvider {
    private(set) var writes: [[StationUserDataChange]] = []
    func writeUserData(_ changes: [StationUserDataChange]) async throws {
        writes.append(changes)
    }
}

private struct NoopWriteStationsProvider: WriteStationsProvider {
    func writeStations(_: [TrainTime.Station]) async throws {}
}

/// Enough of a station component to satisfy the dependency; no test opens
/// a station.
private struct UnusedStationProviders: WriteStationProvider, StationStreamProvider, WriteTrainsProvider, TrainsStreamProvider {
    func writeStation(_: TrainTime.Station) async throws {}
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<TrainTime.Station?> {
        AsyncThrowingStream<TrainTime.Station?, any Error> { $0.finish() }
    }
    func writeTrainAtStop(_: [TrainAtStop],
                          at stop: String,
                          keeping identifiers: Set<String>) async throws {}
    func trains(identifiers: [String],
                at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]> {
        AsyncThrowingStream<[TrainAtStop], any Error> { $0.finish() }
    }
}

// MARK: - Harness

@MainActor
private struct Harness {
    let streams = TestStationsStreamProvider()
    let writes = RecordingUserDataProvider()
    let state: StationListState
    init() {
        let apiService = TestAPIService()
        let providers = UnusedStationProviders()
        let component = StationListComponent(
            stationsService: StationsService(
                fetchAllStationsProvider: apiService,
                writeStationsProvider: NoopWriteStationsProvider(),
                stationsStreamProvider: streams,
                writeUserDataForStationProvider: writes
            ),
            logExportService: LogExportService()
        ) {
            StationComponent(
                stationService: StationService(fetchStationProvider: apiService,
                                               writeStationProvider: providers,
                                               stationStreamProvider: providers),
                trainService: TrainService(fetchTrainProvider: apiService,
                                           writeTrainsProvider: providers,
                                           trainsStreamProvider: providers),
                calendar: .current
            )
        }
        state = StationListState(component: component)
    }
    /// Starts observing and delivers `stations` as the database would.
    func start(with stations: [TrainTime.Station]) async throws {
        try await state.load()
        await streams.yield(stations)
        #expect(await waitUntil {
            state.allRows.map(\.station.code) == stations.map(\.code)
        })
    }
    var favoriteCodes: [String] {
        state.favoriteRows.map(\.station.code)
    }
    var otherCodes: [String] {
        state.otherRows.map(\.station.code)
    }
    func sortOrder(of code: String) -> Double? {
        state.favoriteRows.first { $0.station.code == code }?.station.favoriteSortOrder
    }
    /// Polls until `condition` holds or the timeout passes.
    @discardableResult
    func waitUntil(timeout: Duration = .seconds(5),
                   _ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
    /// Long enough for the write debounce to have fired if it was going to.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(400))
    }
}

private func favorite(_ station: TrainTime.Station,
                      at sortOrder: Double?) -> TrainTime.Station {
    var station = station
    station.isFavorite = true
    station.favoriteSortOrder = sortOrder
    return station
}

private func change(_ code: String,
                    isFavorite: Bool? = true,
                    _ sortOrder: Double?) -> StationUserDataChange {
    StationUserDataChange(code: code,
                          isFavorite: isFavorite,
                          sortOrder: sortOrder)
}

// MARK: - Tests

@MainActor
struct StationListStateTests {
    @Test func rowsAreSplitIntoFavoritesAndTheRest() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1),
                                       .nypFixture,
                                       .syrFixture])
        #expect(harness.favoriteCodes == ["UCA", "ROC"])
        #expect(harness.otherCodes == ["NYP", "SYR"])
    }
    @Test func dragToTopReordersAtOnceAndWritesOnlyTheMovedStation() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1),
                                       favorite(.syrFixture, at: 2),
                                       .nypFixture])

        harness.state.moveFavorites(fromOffsets: [2],
                                    toOffset: 0)

        #expect(harness.favoriteCodes == ["SYR", "UCA", "ROC"])
        #expect(harness.state.allRows.map(\.station.code) == ["SYR", "UCA", "ROC", "NYP"])
        #expect(harness.sortOrder(of: "SYR") == -1)
        #expect(await harness.waitUntil {
            await harness.writes.writes == [[change("SYR", -1)]]
        })
    }
    @Test func moveUpThenToBottomCoalesceIntoOneWrite() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1),
                                       favorite(.syrFixture, at: 2)])

        harness.state.moveFavorite(code: "SYR",
                                   by: -1)
        #expect(harness.favoriteCodes == ["UCA", "SYR", "ROC"])
        #expect(harness.sortOrder(of: "SYR") == 0.5)

        // Uses the position SYR is about to get, not the one it had.
        harness.state.moveFavoriteToBottom(code: "UCA")
        #expect(harness.favoriteCodes == ["SYR", "ROC", "UCA"])
        #expect(harness.sortOrder(of: "UCA") == 2)

        #expect(await harness.waitUntil {
            await harness.writes.writes.count == 1
        })
        #expect(Set(await harness.writes.writes.first ?? []) == [change("SYR", 0.5),
                                                                 change("UCA", 2)])
    }
    @Test func movingPastTheEndsDoesNothing() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1)])

        harness.state.moveFavorite(code: "UCA",
                                   by: -1)
        harness.state.moveFavoriteToTop(code: "UCA")
        harness.state.moveFavoriteToBottom(code: "ROC")
        harness.state.moveFavorites(fromOffsets: [5],
                                    toOffset: 0)
        await harness.settle()

        #expect(harness.favoriteCodes == ["UCA", "ROC"])
        #expect(await harness.writes.writes.isEmpty)
    }
    @Test func favoritesWithoutPositionsAreReindexedOnFirstMove() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: nil),
                                       favorite(.rocFixture, at: nil),
                                       favorite(.syrFixture, at: nil)])

        harness.state.moveFavorite(code: "SYR",
                                   by: -1)

        #expect(harness.favoriteCodes == ["UCA", "SYR", "ROC"])
        #expect(await harness.waitUntil {
            await harness.writes.writes == [[change("UCA", 0),
                                             change("SYR", 1),
                                             change("ROC", 2)]]
        })
    }
    @Test func favoritingAppendsToTheEndOfTheFavorites() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1),
                                       .nypFixture,
                                       .syrFixture])

        harness.state.toggleFavorite(code: "NYP")

        #expect(harness.favoriteCodes == ["UCA", "ROC", "NYP"])
        #expect(harness.otherCodes == ["SYR"])
        #expect(harness.state.favoriteRows.last?.station.isFavorite == true)
        #expect(await harness.waitUntil {
            await harness.writes.writes == [[change("NYP", 2)]]
        })
    }
    @Test func unfavoritingReturnsTheStationToItsPlaceByName() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1),
                                       .nypFixture,
                                       .syrFixture])

        harness.state.toggleFavorite(code: "ROC")

        #expect(harness.favoriteCodes == ["UCA"])
        #expect(harness.otherCodes == ["NYP", "ROC", "SYR"])
        #expect(harness.state.otherRows[1].station.isFavorite == nil)
        #expect(await harness.waitUntil {
            await harness.writes.writes == [[change("ROC", isFavorite: nil, nil)]]
        })
    }
    @Test func theDatabaseEchoOfAMoveLeavesTheRowsAlone() async throws {
        let harness = Harness()
        try await harness.start(with: [favorite(.ucaFixture, at: 0),
                                       favorite(.rocFixture, at: 1),
                                       .nypFixture])
        harness.state.moveFavorite(code: "ROC",
                                   by: -1)
        let rowsAfterMove = harness.state.allRows

        // The observation reports what was just written.
        await harness.streams.yield([favorite(.rocFixture, at: -1),
                                     favorite(.ucaFixture, at: 0),
                                     .nypFixture])
        await harness.settle()

        #expect(harness.state.allRows == rowsAfterMove)
        #expect(harness.favoriteCodes == ["ROC", "UCA"])
    }
}
