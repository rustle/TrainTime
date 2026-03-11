import Foundation
import GRDB

final class Database: Sendable {
    let name: String
    private let migrator: Migrator = .init()
    init(name: String) {
        self.name = name
    }
    private func checkedCachesDirectory() throws -> String {
        let cachesURL = URL.cachesDirectory
        _ = try cachesURL.checkResourceIsReachable()
        return cachesURL.appendingPathComponent(name).path
    }
    func newConnection() throws -> DatabasePool {
        return try DatabasePool(path: try checkedCachesDirectory())
    }
    func runMigrations(_ pool: DatabasePool) async throws {
        try await migrator.runMigrations(pool)
    }
}

private actor Migrator {
    private enum MigrationState {
        case waiting
        case migrating
        case done
    }
    private var state = MigrationState.waiting
    private var migrator: DatabaseMigrator = .init()
    func runMigrations(_ pool: DatabasePool) throws {
        guard state == .waiting else {
            return
        }
        state = .migrating
        migrator.registerMigration("v1") { db in
            try db.create(table: "station") { t in
                t.primaryKey(TTStation.Columns.code.name, .text)
                t.column("name", .text)
                t.column("tz", .text)
                t.column("lat", .real)
                t.column("lon", .real)
                t.column("address1", .text)
                t.column("address2", .text)
                t.column("city", .text)
                t.column("zip", .text)
                t.column("trainIdentifiers", .blob).notNull()
                t.column("normalizedCode", .text)
                t.column("normalizedName", .text)
                t.column("normalizedCity", .text)
                t.column("isFavorite", .boolean)
            }
            try db.create(table: "train") { t in
                t.primaryKey("trainID", .text)
                t.column("routeName", .text)
                t.column("trainNum", .text).notNull()
                t.column("trainNumRaw", .text).notNull()
                t.column("lat", .real)
                t.column("lon", .real)
                t.column("iconColor", .text)
                t.column("heading", .blob)
                t.column("eventCode", .text)
                t.column("eventTZ", .text)
                t.column("eventName", .text)
                t.column("origCode", .text)
                t.column("originTZ", .text)
                t.column("origName", .text)
                t.column("destCode", .text)
                t.column("destTZ", .text)
                t.column("destName", .text)
                t.column("trainState", .blob)
                t.column("velocity", .real)
                t.column("statusMsg", .text)
                t.column("createdAt", .real).notNull()
                t.column("updatedAt", .real).notNull()
                t.column("lastValTS", .real).notNull()
                t.column("objectID", .integer)
                t.column("provider", .text)
                t.column("providerShort", .text)
                t.column("onlyOfTrainNum", .boolean)
                t.column("alerts", .blob).notNull()
            }
            try db.create(table: "stop") { t in
                t.column("trainID", .text).notNull()
                    .references("train", onDelete: .cascade)
                t.column("stationCode", .text).notNull()
                t.column("schArr", .real).notNull()
                t.column("schDep", .real).notNull()
                t.column("arr", .real)
                t.column("dep", .real)
                t.column("platform", .text)
                t.column("status", .blob)
                t.primaryKey(["trainID", "stationCode"])
            }
        }
        try migrator.migrate(pool)
        state = .done
    }
}
