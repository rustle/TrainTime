import Testing
@testable import TrainTime

struct TrainTimeTests {
    @Test func fetchAllStationsContainsUCA() async throws {
        let client = TestClient()
        let stations = try await client.fetchAllStations()
        #expect(stations["UCA"] == .ucaFixture)
    }
    @Test func fetchStationUCA() async throws {
        let client = TestClient()
        let station = try await client.fetchStation(id: "UCA")
        #expect(station == .ucaFixture)
    }
    @Test func stationsServiceLoadsAllStations() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let service = StationsService(
            fetchAllStationsProvider: TestClient(),
            writeStationsProvider: testDB.connection,
            stationsStreamProvider: testDB.connection
        )

        try await service.load()

        var iterator = try await service.stations().makeAsyncIterator()
        let stations = try #require(try await iterator.next())

        let fixtures: Set<TTStation> = [.ucaFixture, .rocFixture, .syrFixture, .nypFixture]
        #expect(Set(stations) == fixtures)
    }
    @Test func stationServiceLoadsUCAAndTrain48() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let client = TestClient()
        let stationService = StationService(
            fetchStationProvider: client,
            writeStationProvider: testDB.connection,
            stationStreamProvider: testDB.connection
        )
        let trainService = TrainService(
            fetchTrainProvider: client,
            writeTrainsProvider: testDB.connection,
            trainsStreamProvider: testDB.connection
        )

        let ucaTrainIdentifiers = TTStation.ucaFixture.trainIdentifiers
        try await stationService.load(id: "UCA")
        try await trainService.load(identifiers: ucaTrainIdentifiers)

        var stationIterator = try await stationService.station(code: "UCA").makeAsyncIterator()
        let station = try #require(try await stationIterator.next())

        var trainIterator = try await trainService.trains(identifiers: ucaTrainIdentifiers,
                                                          stationCode: "UCA").makeAsyncIterator()
        let trains = try #require(try await trainIterator.next())

        #expect(station == .ucaFixture)
        #expect(trains.map(\.trainID) == ["280-2", "284-2", "63-2", "48-1", "281-2", "64-2"])
    }

    @Test func trainsStreamWithStationCodeOnlyLoadsStopForThatStation() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let trainService = TrainService(
            fetchTrainProvider: TestClient(),
            writeTrainsProvider: testDB.connection,
            trainsStreamProvider: testDB.connection
        )

        let identifiers = TTStation.ucaFixture.trainIdentifiers
        try await trainService.load(identifiers: identifiers)

        var iterator = try await trainService.trains(identifiers: identifiers,
                                                     stationCode: "UCA").makeAsyncIterator()
        let trains = try #require(try await iterator.next())

        for train in trains {
            #expect(train.stops.keys.allSatisfy { $0 == "UCA" })
        }
    }

    @Test func trainsStreamWithoutStationCodeLoadsAllStops() async throws {
        let testDB = try TestDatabase.make()
        defer { try? testDB.closeAndDelete() }
        try await testDB.database.runMigrations(testDB.connection)

        let trainService = TrainService(
            fetchTrainProvider: TestClient(),
            writeTrainsProvider: testDB.connection,
            trainsStreamProvider: testDB.connection
        )

        try await trainService.load(identifiers: ["48-1"])

        var iterator = try await trainService.trains(identifiers: ["48-1"],
                                                     stationCode: nil).makeAsyncIterator()
        let trains = try #require(try await iterator.next())
        let train = try #require(trains.first)

        #expect(train.stops == TTTrain.train48Fixture.stops)
    }
}
