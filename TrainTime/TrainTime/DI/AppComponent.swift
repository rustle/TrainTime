import GRDB

protocol AppDependency: Sendable {
    func makeStationListComponent() -> StationListComponent
}

struct AppComponent: AppDependency {
    static func makeProductionAppComponent() async throws -> Self {
        let database = Database(name: "train.db")
        let connection = try database.newConnection()
        try await database.runMigrations(connection)
        return AppComponent {
            TTClient()
        } databaseFactory: {
            (database, connection)
        }
    }
    let client: TTClient
    let database: Database
    let databaseConnection: DatabasePool
    func makeStationListComponent() -> StationListComponent {
        StationListComponent(
            stationsService: .init(
                fetchAllStationsProvider: client,
                writeStationsProvider: databaseConnection,
                stationsStreamProvider: databaseConnection
            )
        ) {
            StationComponent(
                stationService: .init(
                    fetchStationProvider: client,
                    writeStationProvider: databaseConnection,
                    stationStreamProvider: databaseConnection
                ),
                trainService: .init(
                    fetchTrainProvider: client,
                    writeTrainsProvider: databaseConnection,
                    trainsStreamProvider: databaseConnection
                )
            )
        }
    }
    init(clientFactory: () -> TTClient,
         databaseFactory: () -> (Database, DatabasePool)) {
        self.client = clientFactory()
        let (database, databaseConnection) = databaseFactory()
        self.database = database
        self.databaseConnection = databaseConnection
    }
}

#if DEBUG
struct PreviewAppComponent: AppDependency {
    // TODO: Try out DatabaseQueue and in memory DB
    private actor PreviewDatabase: WriteStationsProvider, StationsStreamProvider, WriteStationProvider, StationStreamProvider, WriteTrainsProvider, TrainsStreamProvider {
        private var lastStations: [TTStation] = []
        private var trains: [String:TTTrain] = [:]
        func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]> {
            _stations
        }
        func writeStations(_ stations: [TTStation]) async throws {
            lastStations = stations
            _stationsContinuation.yield(stations.sorted { lhs, rhs in
                (lhs.normalizedName ?? lhs.normalizedCode) < (rhs.normalizedName ?? rhs.normalizedCode)
            })
        }
        func updateStation(code: String,
                           isFavorite: Bool?) async throws {
            let index = lastStations.firstIndex { station in
                station.code == code
            }
            if let index {
                var stations = lastStations
                var station = stations[index]
                station.isFavorite = isFavorite
                stations[index] = station
                try await writeStations(stations)
            }
        }
        func writeStation(_ station: TTStation) async throws {
            let index = lastStations.firstIndex { nextStation in
                nextStation.code == station.code
            }
            if let index {
                lastStations[index] = station
            } else {
                lastStations.append(station)
            }
            _stationContinuation.yield(station)
        }
        func station(code: String) async throws -> any AsyncThrowingSendableSequence<TTStation?> {
            _station
        }
        func writeTrains(_ trains: [TTTrain]) async throws {
            trains.forEach { train in
                self.trains[train.trainID] = train
            }
        }
        func trains(identifiers: [String],
                    stationCode: String?) async throws -> any AsyncThrowingSendableSequence<[TTTrain]> {
            fatalError()
        }
        private let _stations: AsyncThrowingStream<[TTStation], any Error>
        private let _station: AsyncThrowingStream<TTStation?, any Error>
        let _stationsContinuation: AsyncThrowingStream<[TTStation], any Error>.Continuation
        let _stationContinuation: AsyncThrowingStream<TTStation?, any Error>.Continuation
        init() {
            let (stations, stationsContinuation) = AsyncThrowingStream<[TTStation], any Error>.makeStream()
            _stations = stations
            self._stationsContinuation = stationsContinuation
            let (station, stationContinuation) = AsyncThrowingStream<TTStation?, any Error>.makeStream()
            _station = station
            _stationContinuation = stationContinuation
        }
    }
    func makeStationListComponent() -> StationListComponent {
        let previewClient = TTClient()
        let previewDatabase = PreviewDatabase()
        let stationsService = StationsService(
            fetchAllStationsProvider: previewClient,
            writeStationsProvider: previewDatabase,
            stationsStreamProvider: previewDatabase
        )
        let stationService = StationService(
            fetchStationProvider: previewClient,
            writeStationProvider: previewDatabase,
            stationStreamProvider: previewDatabase
        )
        let trainService = TrainService(
            fetchTrainProvider: previewClient,
            writeTrainsProvider: previewDatabase,
            trainsStreamProvider: previewDatabase
        )
        return StationListComponent(
            stationsService: stationsService) {
                StationComponent(stationService: stationService,
                                 trainService: trainService)
            }
    }
}
#endif // DEBUG
