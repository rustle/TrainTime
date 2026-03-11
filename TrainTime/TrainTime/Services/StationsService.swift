import GRDB
import os
import SwiftConcurrencySerialQueue

protocol FetchAllStationsProvider: Sendable {
    func fetchAllStations() async throws -> TTStationResponse
}

extension TTClient: FetchAllStationsProvider {}

protocol WriteStationsProvider: Sendable {
    func writeStations(_: [TTStation]) async throws -> Void
}

extension DatabasePool: WriteStationsProvider {
    func writeStations(_ stations: [TTStation]) async throws -> Void {
        try await write { db in
            let codes = Set(stations.map(\.code))
            try TTStation
                    .filter(!codes.contains(TTStation.Columns.code))
                    .deleteAll(db)
            try stations.forEach { try $0.upsert(db) }
        }
    }
}

protocol StationsStreamProvider: Sendable {
    var stations: any AsyncSequence<[TTStation], any Error> { get }
}

extension DatabasePool: StationsStreamProvider {
    var stations: any AsyncSequence<[TTStation], any Error> {
        ValueObservation
            .tracking { db in
                try TTStation
                    .order(sql: "COALESCE(normalizedName, normalizedCode) COLLATE NOCASE ASC")
                    .fetchAll(db)
            }
            //.print()
            .values(in: self)
    }
}

struct StationsService {
    init(client: TTClient,
         databaseConnection: DatabasePool) {
        self.fetchAllStationsProvider = client
        self.writeStationsProvider = databaseConnection
        self.stationsStreamProvider = databaseConnection
    }
    private let fetchAllStationsProvider: FetchAllStationsProvider
    private let writeStationsProvider: WriteStationsProvider
    private let stationsStreamProvider: StationsStreamProvider
    init(fetchAllStationsProvider: FetchAllStationsProvider,
         writeStationsProvider: WriteStationsProvider,
         stationsStreamProvider: StationsStreamProvider) {
        self.fetchAllStationsProvider = fetchAllStationsProvider
        self.writeStationsProvider = writeStationsProvider
        self.stationsStreamProvider = stationsStreamProvider
    }
    private let loadQueue = SerialQueueThrowing()
    func load() async throws {
        Logger.service.debug("Fetching stations")
        let stations = try await loadQueue
            .enqueue { _ in
                try await fetchAllStationsProvider.fetchAllStations()
            }
        Logger.service.debug("Saving stations")
        try await writeStationsProvider.writeStations(Array(stations.values))
    }
    var stations: any AsyncSequence<[TTStation], any Error> {
        stationsStreamProvider.stations
    }
}
