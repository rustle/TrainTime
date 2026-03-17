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
        let stations = try await apiService.fetchAllStations()
        #expect(stations["UCA"] == .ucaFixture)
    }
    @Test func fetchStationUCA() async throws {
        let apiService = TestAPIService()
        let station = try await apiService.fetchStation(id: "UCA")
        #expect(station == .ucaFixture)
    }
    @Test func stationsServiceLoadsAllStations() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let service = StationsService(
            fetchAllStationsProvider: TestAPIService(),
            writeStationsProvider: testDB.connection,
            stationsStreamProvider: testDB.connection,
            userDataStationsProvider: TestUserDataProvider()
        )

        try await service.load()

        let stations = try #require(
            try await service.stations().firstArrayFromStream()
        )

        let fixtures: Set<TTStation> = [.ucaFixture, .rocFixture, .syrFixture, .nypFixture]
        #expect(Set(stations) == fixtures)
    }
    @Test func stationServiceLoadsUCAAndTrain48() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let apiService = TestAPIService()
        let stationService = StationService(
            fetchStationProvider: apiService,
            writeStationProvider: testDB.connection,
            stationStreamProvider: testDB.connection
        )
        let trainService = TrainService(
            fetchTrainProvider: apiService,
            writeTrainsProvider: testDB.connection,
            trainsStreamProvider: testDB.connection
        )

        let ucaTrainIdentifiers = TTStation.ucaFixture.trainIdentifiers
        try await stationService.load(id: "UCA")
        try await trainService.load(identifiers: ucaTrainIdentifiers)

        let station = try #require(
            try await stationService.station(code: "UCA")
                .firstElementFromStream()
        )

        let trains = try #require(
            try await trainService.trains(identifiers: ucaTrainIdentifiers,
                                          stationCode: "UCA")
                .firstArrayFromStream()
        )

        #expect(station == .ucaFixture)
        #expect(trains.map(\.trainID) == ["280-2", "284-2", "63-2", "48-1", "281-2", "64-2"])
    }
    @Test func trainsStreamWithStationCodeOnlyLoadsStopForThatStation() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let trainService = TrainService(
            fetchTrainProvider: TestAPIService(),
            writeTrainsProvider: testDB.connection,
            trainsStreamProvider: testDB.connection
        )

        let identifiers = TTStation.ucaFixture.trainIdentifiers
        try await trainService.load(identifiers: identifiers)

        let trains = try #require(
            try await trainService.trains(identifiers: identifiers,
                                                       stationCode: "UCA")
                .firstArrayFromStream()
        )

        for train in trains {
            #expect(train.stops.keys.allSatisfy { $0 == "UCA" })
        }
    }
    @Test func trainsStreamWithoutStationCodeLoadsAllStops() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let trainService = TrainService(
            fetchTrainProvider: TestAPIService(),
            writeTrainsProvider: testDB.connection,
            trainsStreamProvider: testDB.connection
        )

        try await trainService.load(identifiers: ["48-1"])

        let train = try #require(
            try await trainService.trains(identifiers: ["48-1"],
                                          stationCode: nil)
                .firstElementFromFirstArrayFromStream()
        )
        #expect(train.stops == TTTrain.train48Fixture.stops)
    }
}
