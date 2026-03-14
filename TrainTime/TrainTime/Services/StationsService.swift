import Foundation
import GRDB
import os
import SwiftConcurrencySerialQueue

protocol FetchAllStationsProvider: Sendable {
    func fetchAllStations() async throws -> TTStationResponse
}

extension TTClient: FetchAllStationsProvider {}

protocol WriteStationsProvider: Sendable {
    func writeStations(_: [TTStation]) async throws -> Void
    func updateStation(code: String,
                       isFavorite: Bool?) async throws -> Void
}

extension DatabasePool: WriteStationsProvider {
    func writeStations(_ stations: [TTStation]) async throws {
        try await write { db in
            let codes = Set(stations.map(\.code))
            try TTStation
                .filter(!codes.contains(TTStation.Columns.code))
                .deleteAll(db)
            try stations.forEach { try $0.upsert(db) }
        }
    }
    func updateStation(code: String,
                       isFavorite: Bool?) async throws {
        try await write { db in
            let station = try TTStation
                .filter(TTStation.Columns.code == code)
                .fetchOne(db)
            if var station {
                do {
                    station.isFavorite = isFavorite
                    try station.update(db)
                } catch {
                    Logger.database.error("Station not updated \(code) - \(String(describing: isFavorite)) - \(error.localizedDescription)")
                    throw error
                }
            }
        }
    }
}

protocol StationsStreamProvider: Sendable {
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]>
}

extension DatabasePool: StationsStreamProvider {
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]> {
        ValueObservation
            .tracking { db in
                try TTStation
                    .order(sql: """
                                COALESCE(isFavorite, 0) DESC, 
                                COALESCE(normalizedName, normalizedCode) ASC
                                """)
                    .fetchAll(db)
            }
            .values(in: self)
    }
}

struct StationsService: Sendable {
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
    func updateStation(code: String,
                       isFavorite: Bool?) async throws {
        try await writeStationsProvider
            .updateStation(code: code,
                           isFavorite: isFavorite)
    }
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]> {
        try await stationsStreamProvider.stations()
    }
}
