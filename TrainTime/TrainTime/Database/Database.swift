import Foundation
import GRDB

final class Database: Sendable {
    let name: String
    let directoryURL: URL?
    private let migrator: Migrator = .init()
    init(name: String,
         directoryURL: URL? = nil) {
        self.name = name
        self.directoryURL = directoryURL
    }
    private func checkedPath() throws -> String {
        let url = directoryURL ?? URL.cachesDirectory
        _ = try url.checkResourceIsReachable()
        return url.appendingPathComponent(name).path
    }
    func newConnection() throws -> DatabasePool {
        return try DatabasePool(path: try checkedPath())
    }
    func runMigrations(_ pool: DatabasePool) async throws {
        try await migrator.runMigrations(pool)
    }
}
