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
    static func deleteProductionUserData() {
        Database.deleteIfExists(name: "userdata.db",
                                directoryURL: URL.documentsDirectory)
    }
    static func makeProductionAppComponent() async throws -> Self {
        let cache = Database(name: "cache.db",
                             directoryURL: URL.cachesDirectory,
                             migrator: CacheMigrator())
        let cacheConnection: DatabasePool
        do {
            cacheConnection = try cache.newConnection()
            try await cache.runMigrations(cacheConnection)
        } catch {
            throw DatabaseSetupError(database: .cache,
                                     underlying: error)
        }
        let userData = Database(name: "userdata.db",
                                directoryURL: URL.documentsDirectory,
                                migrator: UserDataMigrator())
        let userDataConnection: DatabasePool
        do {
            userDataConnection = try userData.newConnection()
            try await userData.runMigrations(userDataConnection)
        } catch {
            throw DatabaseSetupError(database: .userData,
                                     underlying: error)
        }
        return AppComponent {
            APIService()
        } databaseFactory: {
            (cache, cacheConnection,
             userData, userDataConnection)
        }
    }
    let apiService: APIService
    let logExportService = LogExportService()
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
            ),
            logExportService: logExportService
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
                ),
                calendar: .current
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
    /// Previews are pinned to one calendar so day boundaries and "today"
    /// don't depend on the machine rendering them.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()
    // TODO: Try out DatabaseQueue and in memory DB
    private actor PreviewDatabase: WriteStationsProvider, StationsStreamProvider, WriteUserDataForStationProvider, WriteStationProvider, StationStreamProvider, WriteTrainsProvider, TrainsStreamProvider {
        private var lastStations: [Station] = []
        private var lastFavorites: Set<String> = Set()
        private var trains: [String:TrainAtStop] = [:]
        func stations() async throws -> any AsyncThrowingSendableSequence<[Station]> {
            _stations
        }
        func writeStations(_ stations: [Station]) async throws {
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
        func writeStation(_ station: Station) async throws {
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
        func station(code: String) async throws -> any AsyncThrowingSendableSequence<Station?> {
            _station
        }
        func writeTrainAtStop(_ trains: [TrainAtStop],
                              at stop: String,
                              keeping identifiers: Set<String>) async throws {
            self.trains = self.trains.filter { _, value in
                value.stop.code != stop || identifiers.contains(value.train.trainID)
            }
            for train in trains {
                self.trains["\(train.train.trainID):\(train.stop.code)"] = train
            }
            // Match the database: emit everything still known for this stop,
            // not just the trains this write happened to bring in.
            let known = trainsAtStop(stop)
            for continuation in trainsContinuations[stop, default: [:]].values {
                continuation.yield(known)
            }
        }
        func trains(identifiers: [String],
                    at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]> {
            // One stream per observer, kept per stop. A second observer must
            // not end the first one's stream. Ending it strands that view,
            // because a completed stream leaves StationViewState holding a
            // claim on identifiers it is no longer observing, so it never
            // rebuilds.
            let (stream, continuation) = AsyncThrowingStream<[TrainAtStop], any Error>.makeStream()
            let token = UUID()
            trainsContinuations[stop, default: [:]][token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeTrainsContinuation(token,
                                                         at: stop)
                }
            }
            // Deliver what is already known, the way a database observation
            // does, so a rebuilt observation isn't empty until the next write.
            continuation.yield(trainsAtStop(stop))
            return stream
        }
        private func removeTrainsContinuation(_ token: UUID,
                                              at stop: String) {
            trainsContinuations[stop]?.removeValue(forKey: token)
            if trainsContinuations[stop]?.isEmpty == true {
                trainsContinuations.removeValue(forKey: stop)
            }
        }
        private func trainsAtStop(_ stop: String) -> [TrainAtStop] {
            trains.values.filter { $0.stop.code == stop }
        }
        private let _stations: AsyncThrowingStream<[Station], any Error>
        private let _userData: AsyncThrowingStream<Set<String>, any Error>
        private let _station: AsyncThrowingStream<Station?, any Error>
        let _stationsContinuation: AsyncThrowingStream<[Station], any Error>.Continuation
        let _userDataContinuation: AsyncThrowingStream<Set<String>, any Error>.Continuation
        let _stationContinuation: AsyncThrowingStream<Station?, any Error>.Continuation
        private var trainsContinuations: [String: [UUID: AsyncThrowingStream<[TrainAtStop], any Error>.Continuation]] = [:]
        init() {
            let (stations, stationsContinuation) = AsyncThrowingStream<[Station], any Error>.makeStream()
            _stations = stations
            _stationsContinuation = stationsContinuation
            let (userData, userDataContinuation) = AsyncThrowingStream<Set<String>, any Error>.makeStream()
            _userData = userData
            _userDataContinuation = userDataContinuation
            let (station, stationContinuation) = AsyncThrowingStream<Station?, any Error>.makeStream()
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
            stationsService: stationsService,
            logExportService: LogExportService()
        ) {
                StationComponent(stationService: stationService,
                                 trainService: trainService,
                                 calendar: Self.calendar)
            }
    }
}
#endif // DEBUG
