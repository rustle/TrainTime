import Amtrak
import Foundation
import Testing
@testable import TrainTime

// MARK: - Doubles

/// Hands out one station stream per request and lets the test drive it.
private actor TestStationStreamProvider: StationStreamProvider {
    enum Failure: Error {
        case unavailable
    }
    private var continuations: [AsyncThrowingStream<TrainTime.Station?, any Error>.Continuation] = []
    var requestCount: Int {
        continuations.count
    }
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<TrainTime.Station?> {
        let (stream, continuation) = AsyncThrowingStream<TrainTime.Station?, any Error>.makeStream()
        continuations.append(continuation)
        return stream
    }
    func yield(_ station: TrainTime.Station?) {
        for continuation in continuations {
            continuation.yield(station)
        }
    }
    /// Ends every stream handed out so far with an error.
    func fail() {
        for continuation in continuations {
            continuation.finish(throwing: Failure.unavailable)
        }
    }
}

/// Hands out one trains stream per request, records every request, and lets
/// the test drive any of the streams it has handed out.
private actor TestTrainsStreamProvider: TrainsStreamProvider {
    struct Request: Equatable {
        let identifiers: [String]
        let stop: String
    }
    enum Failure: Error {
        case unavailable
    }
    private(set) var requests: [Request] = []
    private var continuations: [AsyncThrowingStream<[TrainAtStop], any Error>.Continuation] = []
    private var failNextRequest = false
    func failNext() {
        failNextRequest = true
    }
    func trains(identifiers: [String],
                at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]> {
        if failNextRequest {
            failNextRequest = false
            throw Failure.unavailable
        }
        requests.append(Request(identifiers: identifiers,
                                stop: stop))
        let (stream, continuation) = AsyncThrowingStream<[TrainAtStop], any Error>.makeStream()
        continuations.append(continuation)
        return stream
    }
    func yield(_ trains: [TrainAtStop],
               toRequest index: Int) {
        continuations[index].yield(trains)
    }
}

private struct TestFetchStationProvider: FetchStationProvider {
    let station: TrainTime.Station
    func fetchStation(code: String) async throws -> TrainTime.Station {
        station
    }
}

private struct NoopWriteStationProvider: WriteStationProvider {
    func writeStation(_: TrainTime.Station) async throws {}
}

/// Records the `keeping:` set of every write so a test can see which list a
/// load ran against.
private actor RecordingWriteTrainsProvider: WriteTrainsProvider {
    private(set) var kept: [Set<String>] = []
    func writeTrainAtStop(_: [TrainAtStop],
                          at stop: String,
                          keeping identifiers: Set<String>) async throws {
        kept.append(identifiers)
    }
}

// MARK: - Harness

@MainActor
private struct Harness {
    let stationStreams = TestStationStreamProvider()
    let trainsStreams = TestTrainsStreamProvider()
    let writeTrains = RecordingWriteTrainsProvider()
    let state: StationViewState
    /// - Parameters:
    ///   - station: What the view starts with, as if handed over from the list.
    ///   - refreshedStation: What a `refreshStation: true` load fetches.
    init(station: TrainTime.Station = .ucaFixture,
         refreshedStation: TrainTime.Station = .ucaFixture) {
        let component = StationComponent(
            stationService: StationService(
                fetchStationProvider: TestFetchStationProvider(station: refreshedStation),
                writeStationProvider: NoopWriteStationProvider(),
                stationStreamProvider: stationStreams
            ),
            trainService: TrainService(
                fetchTrainProvider: TestAPIService(),
                writeTrainsProvider: writeTrains,
                trainsStreamProvider: trainsStreams
            )
        )
        state = StationViewState(station: station,
                                 component: component)
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
    /// Gives the observation tasks a moment to publish anything they hold.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }
}

private let train48AtUCA = TrainAtStop(
    train: .train48Fixture,
    stop: [Stop].train48StopsFixture.first { $0.code == "UCA" }!
)

// MARK: - Tests

@MainActor
struct StationViewStateTests {
    @Test func loadObservesTheStationAndItsTrainList() async throws {
        let harness = Harness()

        try await harness.state.load()

        #expect(await harness.trainsStreams.requests == [
            .init(identifiers: TrainTime.Station.ucaFixture.trainIdentifiers,
                  stop: "UCA"),
        ])
        await harness.trainsStreams.yield([train48AtUCA],
                                          toRequest: 0)
        #expect(await harness.waitUntil {
            harness.state.trains.map(\.train.trainID) == ["48-1"]
        })
    }
    @Test func aChangedTrainListRebuildsTheObservationAndDropsTheOldStream() async throws {
        let harness = Harness()
        try await harness.state.load()

        // The station observation reports a new list.
        await harness.stationStreams.yield(TrainTime.Station(code: "UCA",
                                                   trainIdentifiers: ["48-1"]))
        #expect(await harness.waitUntil {
            await harness.trainsStreams.requests.count == 2
        })
        #expect(await harness.trainsStreams.requests[1] == .init(identifiers: ["48-1"],
                                                                  stop: "UCA"))
        #expect(harness.state.station.trainIdentifiers == ["48-1"])

        // A value from the superseded stream must not reach the view.
        await harness.trainsStreams.yield([train48AtUCA],
                                          toRequest: 0)
        await harness.settle()
        #expect(harness.state.trains.isEmpty)

        // A value from the replacement does.
        await harness.trainsStreams.yield([train48AtUCA],
                                          toRequest: 1)
        #expect(await harness.waitUntil {
            harness.state.trains.map(\.train.trainID) == ["48-1"]
        })
    }
    @Test func anUnchangedTrainListIsNotObservedTwice() async throws {
        let harness = Harness()
        try await harness.state.load()

        await harness.stationStreams.yield(.ucaFixture)
        await harness.stationStreams.yield(.ucaFixture)
        await harness.settle()

        #expect(await harness.trainsStreams.requests.count == 1)
    }
    @Test func refreshLoadsAgainstTheFetchedListNotTheOldOne() async throws {
        let refreshed = TrainTime.Station(code: "UCA",
                                trainIdentifiers: ["48-1", "63-2"])
        let harness = Harness(refreshedStation: refreshed)

        try await harness.state.load(refreshStation: true)

        // The observation follows the fetched list without waiting for the
        // station observation to deliver it.
        #expect(await harness.trainsStreams.requests.last == .init(identifiers: ["48-1", "63-2"],
                                                                    stop: "UCA"))
        // And the trains load keeps exactly that list, not the stale one.
        #expect(await harness.writeTrains.kept == [Set(["48-1", "63-2"])])
    }
    @Test func aFailedObservationReleasesItsClaimSoTheNextLoadRetries() async throws {
        let harness = Harness()
        await harness.trainsStreams.failNext()

        // The failure is logged, not thrown, so the view keeps working.
        try await harness.state.load()
        #expect(await harness.trainsStreams.requests.isEmpty)

        try await harness.state.load()
        #expect(await harness.trainsStreams.requests.count == 1)
    }
    @Test func aFailedStationObservationIsRebuiltByTheNextLoad() async throws {
        let harness = Harness()
        try await harness.state.load()
        #expect(await harness.stationStreams.requestCount == 1)

        await harness.stationStreams.fail()
        try await harness.state.load()

        #expect(await harness.stationStreams.requestCount == 2)
        // And the new observation is live: a changed list still rebuilds trains.
        await harness.stationStreams.yield(TrainTime.Station(code: "UCA",
                                                   trainIdentifiers: ["48-1"]))
        #expect(await harness.waitUntil {
            await harness.trainsStreams.requests.count == 2
        })
    }
    @Test func aNilStationKeepsTheObservationAlive() async throws {
        let harness = Harness()
        try await harness.state.load()

        // A stations refresh can briefly delete the row.
        await harness.stationStreams.yield(nil)
        await harness.settle()
        #expect(harness.state.station == .ucaFixture)

        // When it comes back with a new list the observation must still follow it.
        await harness.stationStreams.yield(TrainTime.Station(code: "UCA",
                                                   trainIdentifiers: ["48-1"]))
        #expect(await harness.waitUntil {
            await harness.trainsStreams.requests.count == 2
        })
        #expect(harness.state.station.trainIdentifiers == ["48-1"])
    }
}
