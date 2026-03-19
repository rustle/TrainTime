import GRDB

protocol WriteStationProvider: Sendable {
    func writeStation(_: TTStation) async throws -> Void
}

extension DatabasePool: WriteStationProvider {
    func writeStation(_ station: TTStation) async throws {
        try await write { db in
            try station.upsert(db)
        }
    }
}
