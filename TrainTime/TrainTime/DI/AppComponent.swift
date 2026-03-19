import Foundation
import GRDB

protocol AppDependency: Sendable {
    func makeStationListComponent() -> StationListComponent
}

struct AppComponent: AppDependency {
    static func deleteProductionCache() {
        Database.deleteIfExists(name: "cache.db",
                                directoryURL: URL.cachesDirectory)
    }
    static func makeProductionAppComponent() async throws -> Self {
        let cache = Database(name: "cache.db",
                             directoryURL: URL.cachesDirectory,
                             migrator: CacheMigrator())
        let cacheConnection = try cache.newConnection()
        try await cache.runMigrations(cacheConnection)
        let userData = Database(name: "userdata.db",
                                directoryURL: URL.documentsDirectory,
                                migrator: UserDataMigrator())
        let userDataConnection = try userData.newConnection()
        try await userData.runMigrations(userDataConnection)
        return AppComponent {
            APIService()
        } databaseFactory: {
            (cache, cacheConnection,
             userData, userDataConnection)
        }
    }
    let apiService: APIService
    let cache: Database
    let cacheConnection: DatabasePool
    let userData: Database
    let userDataConnection: DatabasePool
    func makeStationListComponent() -> StationListComponent {
        StationListComponent(
            stationsService: .init(
                fetchAllStationsProvider: apiService,
                writeStationsProvider: cacheConnection,
                stationsStreamProvider: StationsStreamDatabaseProvider(
                    cacheConnection: cacheConnection,
                    userDataConnection: userDataConnection
                ),
                writeUserDataForStationProvider: userDataConnection
            )
        ) {
            StationComponent(
                stationService: .init(
                    fetchStationProvider: apiService,
                    writeStationProvider: cacheConnection,
                    stationStreamProvider: cacheConnection
                ),
                trainService: .init(
                    fetchTrainProvider: apiService,
                    writeTrainsProvider: cacheConnection,
                    trainsStreamProvider: cacheConnection
                )
            )
        }
    }
    init(apiServiceFactory: () -> APIService,
         databaseFactory: () -> (cache: Database, cacheConnection: DatabasePool,
                                 userData: Database, userDataConnection: DatabasePool)) {
        self.apiService = apiServiceFactory()
        let (cache, cacheConnection,
             userData, userDataConnection) = databaseFactory()
        self.cache = cache
        self.cacheConnection = cacheConnection
        self.userData = userData
        self.userDataConnection = userDataConnection
    }
}

#if DEBUG
struct PreviewAppComponent: AppDependency {
    // TODO: Try out DatabaseQueue and in memory DB
    private actor PreviewDatabase: WriteStationsProvider, StationsStreamProvider, WriteUserDataForStationProvider, WriteStationProvider, StationStreamProvider, WriteTrainsProvider, TrainsStreamProvider {
        private var lastStations: [TTStation] = []
        private var lastFavorites: Set<String> = Set()
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
        func writeUserDataForStation(code: String,
                           isFavorite: Bool?) async throws {
            if isFavorite == true {
                lastFavorites.insert(code)
            } else {
                lastFavorites.remove(code)
            }
            _userDataContinuation.yield(lastFavorites)
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
        private let _userData: AsyncThrowingStream<Set<String>, any Error>
        private let _station: AsyncThrowingStream<TTStation?, any Error>
        let _stationsContinuation: AsyncThrowingStream<[TTStation], any Error>.Continuation
        let _userDataContinuation: AsyncThrowingStream<Set<String>, any Error>.Continuation
        let _stationContinuation: AsyncThrowingStream<TTStation?, any Error>.Continuation
        init() {
            let (stations, stationsContinuation) = AsyncThrowingStream<[TTStation], any Error>.makeStream()
            _stations = stations
            _stationsContinuation = stationsContinuation
            let (userData, userDataContinuation) = AsyncThrowingStream<Set<String>, any Error>.makeStream()
            _userData = userData
            _userDataContinuation = userDataContinuation
            let (station, stationContinuation) = AsyncThrowingStream<TTStation?, any Error>.makeStream()
            _station = station
            _stationContinuation = stationContinuation
        }
    }
    func makeStationListComponent() -> StationListComponent {
        let previewAPIService = APIService()
        let previewDatabase = PreviewDatabase()
        let stationsService = StationsService(
            fetchAllStationsProvider: previewAPIService,
            writeStationsProvider: previewDatabase,
            stationsStreamProvider: previewDatabase,
            writeUserDataForStationProvider: previewDatabase
        )
        let stationService = StationService(
            fetchStationProvider: previewAPIService,
            writeStationProvider: previewDatabase,
            stationStreamProvider: previewDatabase
        )
        let trainService = TrainService(
            fetchTrainProvider: previewAPIService,
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
