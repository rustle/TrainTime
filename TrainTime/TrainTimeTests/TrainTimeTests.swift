import AsyncAlgorithms
import Testing
@testable import TrainTime

extension AsyncSequence {
    func firstArrayFromStream<T>() async throws -> [T]? where Self.Element == [T], Self: Sendable {
        try await first { _ in
            true
        }
    }
    func firstElementFromStream<T>() async throws -> T? where Self.Element == T?, Self: Sendable {
        try await compactMap {
            $0
        }
            .first { _ in
                true
            }
    }
    func firstElementFromFirstArrayFromStream<T>() async throws -> T? where Self.Element == [T], Self: Sendable {
        try await compactMap(\.first)
            .first { _ in
                true
            }
    }
}

struct TrainTimeTests {
    @Test func fetchAllStationsContainsUCA() async throws {
        let apiService = TestAPIService()
        let stations = try await apiService.fetchStations()
        #expect(stations[0] == .ucaFixture)
    }
    @Test func fetchStationUCA() async throws {
        let apiService = TestAPIService()
        let station = try await apiService.fetchStation(code: "UCA")
        #expect(station == .ucaFixture)
    }
    @Test func stationsServiceLoadsAllStations() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.runMigrations()

        let service = StationsService(
            fetchAllStationsProvider: TestAPIService(),
            writeStationsProvider: testDB.cacheConnection,
            stationsStreamProvider: StationsStreamDatabaseProvider(cacheConnection: testDB.cacheConnection,
                                                                   userDataConnection: testDB.userDataConnection),
            writeUserDataForStationProvider: TestUserDataProvider()
        )

        try await service.load()

        let stations = try #require(
            try await service.stations().firstArrayFromStream()
        )

        let fixtures: Set<Station> = [.ucaFixture, .rocFixture, .syrFixture, .nypFixture]
        #expect(Set(stations) == fixtures)
    }
    @Test func stationServiceLoadsUCAAndTrain48() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.runMigrations()

        let apiService = TestAPIService()
        let stationService = StationService(
            fetchStationProvider: apiService,
            writeStationProvider: testDB.cacheConnection,
            stationStreamProvider: testDB.cacheConnection
        )
        let trainService = TrainService(
            fetchTrainProvider: apiService,
            writeTrainsProvider: testDB.cacheConnection,
            trainsStreamProvider: testDB.cacheConnection
        )

        let ucaTrainIdentifiers = Station.ucaFixture.trainIdentifiers
        try await stationService.load(stationCode: "UCA")
        try await trainService.load(identifiers: ucaTrainIdentifiers,
                                    at: "UCA")

        let station = try #require(
            try await stationService.station(code: "UCA")
                .firstElementFromStream()
        )

        let trains = try #require(
            try await trainService.trains(identifiers: ucaTrainIdentifiers,
                                          at: "UCA")
                .firstArrayFromStream()
        )

        #expect(station == .ucaFixture)
        #expect(trains.map(\.train.trainID) == ["280-2", "284-2", "63-2", "48-1", "281-2", "64-2"])
    }
    @Test func trainsStreamWithStationCodeLoadsStopForThatStation() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.runMigrations()

        let trainService = TrainService(
            fetchTrainProvider: TestAPIService(),
            writeTrainsProvider: testDB.cacheConnection,
            trainsStreamProvider: testDB.cacheConnection
        )

        let identifiers = Station.ucaFixture.trainIdentifiers
        try await trainService.load(identifiers: identifiers,
                                    at: "UCA")

        let trains = try #require(
            try await trainService.trains(identifiers: identifiers,
                                          at: "UCA")
                .firstArrayFromStream()
        )

        for train in trains {
            #expect(train.stop.code == "UCA")
        }
    }
}
