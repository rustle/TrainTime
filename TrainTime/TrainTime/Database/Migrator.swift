import Foundation
import GRDB

///
actor Migrator {
    private enum MigrationState {
        case waiting
        case migrating
        case done
    }
    private var state = MigrationState.waiting
    private var migrator: DatabaseMigrator = .init()
    /// 
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
                t.column("heading", .text)
                t.column("eventCode", .text)
                t.column("eventTZ", .text)
                t.column("eventName", .text)
                t.column("origCode", .text)
                t.column("originTZ", .text)
                t.column("origName", .text)
                t.column("destCode", .text)
                t.column("destTZ", .text)
                t.column("destName", .text)
                t.column("trainState", .text)
                t.column("velocity", .real)
                t.column("statusMsg", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("lastValTS", .datetime).notNull()
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
                t.column("schArr", .datetime).notNull()
                t.column("schDep", .datetime).notNull()
                t.column("arr", .datetime)
                t.column("dep", .datetime)
                t.column("platform", .text)
                t.column("status", .text)
                t.primaryKey(["trainID", "stationCode"])
            }
        }
        try migrator.migrate(pool)
        state = .done
    }
}
