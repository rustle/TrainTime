import Foundation
import GRDB

///
final class Database: Sendable {
    let name: String
    let directoryURL: URL
    private let migrator: Migrator
    init(name: String,
         directoryURL: URL,
         migrator: Migrator) {
        self.name = name
        self.directoryURL = directoryURL
        self.migrator = migrator
    }
    static func databaseURL(name: String,
                             directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(name)
    }
    static func deleteIfExists(name: String,
                               directoryURL: URL) {
        try? FileManager.default
            .removeItem(at: databaseURL(name: name,
                                        directoryURL: directoryURL))
    }
    private func checkedPath() throws -> String {
        _ = try directoryURL.checkResourceIsReachable()
        return Database.databaseURL(
            name: name,
            directoryURL: directoryURL
        ).path
    }
    func newConnection() throws -> DatabasePool {
        try DatabasePool(path: try checkedPath())
    }
    func runMigrations(_ pool: DatabasePool) async throws {
        try await migrator.runMigrations(pool)
    }
}
