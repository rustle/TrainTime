import GRDB

protocol WriteStationProvider: Sendable {
    func writeStation(_: Station) async throws -> Void
}

extension DatabasePool: WriteStationProvider {
    func writeStation(_ station: Station) async throws {
        try await write { db in
            try station.upsert(db)
        }
    }
}
