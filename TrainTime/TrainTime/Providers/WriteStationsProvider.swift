import GRDB

protocol WriteStationsProvider: Sendable {
    func writeStations(_: [Station]) async throws -> Void
}

extension DatabasePool: WriteStationsProvider {
    func writeStations(_ stations: [Station]) async throws {
        try await write { db in
            let codes = stations.map(\.code)
            try Station
                .filter(!codes.contains(Station.Columns.code))
                .deleteAll(db)
            try stations.forEach { try $0.upsert(db) }
        }
    }
}
