import AsyncAlgorithms
import Foundation
import GRDB
import os
import SwiftConcurrencySerialQueue

protocol WriteUserDataForStationProvider: Sendable {
    func writeUserDataForStation(code: String,
                                 isFavorite: Bool?) async throws
}

extension DatabasePool: WriteUserDataForStationProvider {
    func writeUserDataForStation(code: String,
                                 isFavorite: Bool?) async throws {
        try await write { db in
            var userData = try StationUserData
                .filter(StationUserData.Columns.code == code)
                .fetchOne(db) ?? StationUserData(code: code,
                                                 isFavorite: nil)
            userData.isFavorite = isFavorite
            try userData.upsert(db)
        }
    }
}

struct StationsService: Sendable {
    private let fetchAllStationsProvider: FetchAllStationsProvider
    private let writeStationsProvider: WriteStationsProvider
    private let stationsStreamProvider: StationsStreamProvider
    private let writeUserDataForStationProvider: WriteUserDataForStationProvider
    init(fetchAllStationsProvider: FetchAllStationsProvider,
         writeStationsProvider: WriteStationsProvider,
         stationsStreamProvider: StationsStreamProvider,
         writeUserDataForStationProvider: WriteUserDataForStationProvider) {
        self.fetchAllStationsProvider = fetchAllStationsProvider
        self.writeStationsProvider = writeStationsProvider
        self.stationsStreamProvider = stationsStreamProvider
        self.writeUserDataForStationProvider = writeUserDataForStationProvider
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
    func writeUserDataForStation(code: String,
                                 isFavorite: Bool?) async throws {
        try await writeUserDataForStationProvider
            .writeUserDataForStation(code: code,
                                     isFavorite: isFavorite)
    }
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]> {
        try await stationsStreamProvider.stations()
    }
}
