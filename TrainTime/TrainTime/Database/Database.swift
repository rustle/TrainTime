import Foundation
import GRDB

// TODO: Consider splitting into two databases — a cache DB for train/station data
// (safely deletable on corruption or migration failure) and a separate persistent
// DB for user data like isFavorite that must survive a cache reset.
final class Database: Sendable {
    let name: String
    let directoryURL: URL?
    private let migrator: Migrator = .init()
    init(name: String,
         directoryURL: URL? = nil) {
        self.name = name
        self.directoryURL = directoryURL
    }
    static func databaseURL(name: String,
                             directoryURL: URL? = nil) -> URL {
        (directoryURL ?? URL.cachesDirectory).appendingPathComponent(name)
    }
    static func deleteIfExists(name: String,
                               directoryURL: URL? = nil) {
        try? FileManager.default.removeItem(at: databaseURL(name: name,
                                                            directoryURL: directoryURL))
    }
    private func checkedPath() throws -> String {
        let dir = directoryURL ?? URL.cachesDirectory
        _ = try dir.checkResourceIsReachable()
        return Database.databaseURL(name: name, directoryURL: directoryURL).path
    }
    func newConnection() throws -> DatabasePool {
        return try DatabasePool(path: try checkedPath())
    }
    func runMigrations(_ pool: DatabasePool) async throws {
        try await migrator.runMigrations(pool)
    }
}
