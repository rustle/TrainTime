import GRDB

protocol WriteStationsProvider: Sendable {
    func writeStations(_: [TTStation]) async throws -> Void
}

extension DatabasePool: WriteStationsProvider {
    func writeStations(_ stations: [TTStation]) async throws {
        try await write { db in
            let codes = stations.map(\.code)
            try TTStation
                .filter(!codes.contains(TTStation.Columns.code))
                .deleteAll(db)
            try stations.forEach { try $0.upsert(db) }
        }
    }
}
