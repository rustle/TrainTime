import AsyncAlgorithms
import Foundation
import GRDB
import os
import SwiftConcurrencySerialQueue

protocol FetchAllStationsProvider: Sendable {
    func fetchAllStations() async throws -> TTStationResponse
}

extension APIService: FetchAllStationsProvider {}

protocol WriteStationsProvider: Sendable {
    func writeStations(_: [TTStation]) async throws -> Void
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
}

protocol UserDataStationsProvider: Sendable {
    func updateStation(code: String,
                       isFavorite: Bool?) async throws
    func stationFavorites() async throws -> any AsyncThrowingSendableSequence<Set<String>>
}

extension DatabasePool: UserDataStationsProvider {
    func updateStation(code: String,
                       isFavorite: Bool?) async throws {
        try await write { db in
            var userData = try StationUserData
                .filter(StationUserData.Columns.code == code)
                .fetchOne(db) ?? StationUserData(code: code, isFavorite: nil)
            userData.isFavorite = isFavorite
            try userData.upsert(db)
        }
    }
    func stationFavorites() async throws -> any AsyncThrowingSendableSequence<Set<String>> {
        ValueObservation
            .tracking { db in
                Set(try StationUserData
                    .filter(StationUserData.Columns.isFavorite == true)
                    .select(StationUserData.Columns.code)
                    .fetchAll(db))
            }
            .values(in: self)
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
                    .order(sql: "COALESCE(normalizedName, normalizedCode) ASC")
                    .fetchAll(db)
            }
            .values(in: self)
    }
}

struct StationsService: Sendable {
    private let fetchAllStationsProvider: FetchAllStationsProvider
    private let writeStationsProvider: WriteStationsProvider
    private let stationsStreamProvider: StationsStreamProvider
    private let userDataStationsProvider: UserDataStationsProvider
    init(fetchAllStationsProvider: FetchAllStationsProvider,
         writeStationsProvider: WriteStationsProvider,
         stationsStreamProvider: StationsStreamProvider,
         userDataStationsProvider: UserDataStationsProvider) {
        self.fetchAllStationsProvider = fetchAllStationsProvider
        self.writeStationsProvider = writeStationsProvider
        self.stationsStreamProvider = stationsStreamProvider
        self.userDataStationsProvider = userDataStationsProvider
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
        try await userDataStationsProvider
            .updateStation(code: code,
                           isFavorite: isFavorite)
    }
    // Bare combineLatest makes the type system shout
    // but a generic wrapper passes along enough type info
    // to keep it happy
    // Swift 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)
    private func combineStations<S1: AsyncSequence, S2: AsyncSequence>(
        _ s1: S1,
        _ s2: S2
    ) -> any AsyncThrowingSendableSequence<[TTStation]> where S1.Element == [TTStation], S2.Element == Set<String>, S1: Sendable, S2: Sendable {
        combineLatest(s1, s2)
            .map { stations, favorites in
                var favoriteStations: [TTStation] = []
                // Reserve the full capacity here
                // because at the end we're going
                // to append the regular stations
                // and don't want to resize
                favoriteStations.reserveCapacity(stations.count)
                var regularStations: [TTStation] = []
                // Reservce the full capacity here
                // because in most cases most stations
                // will be regularStations and we don't
                // want to resize inside the loop
                regularStations.reserveCapacity(stations.count)
                for station in stations {
                    if favorites.contains(station.code) {
                        var station = station
                        station.isFavorite = true
                        favoriteStations.append(station)
                    } else {
                        regularStations.append(station)
                    }
                }
                favoriteStations.append(contentsOf: regularStations)
                return favoriteStations
            }
    }
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]> {
        combineStations(try await stationsStreamProvider.stations(),
                        try await userDataStationsProvider.stationFavorites())
    }
}
