import Foundation
import GRDB

protocol Migrator: Actor {
    func runMigrations(_ pool: DatabasePool) throws
}

private enum MigrationState {
    case waiting
    case migrating
    case done
}

///
actor CacheMigrator: Migrator {
    private var state = MigrationState.waiting
    private var migrator: DatabaseMigrator = .init()
    /// 
    func runMigrations(_ pool: DatabasePool) throws {
        guard state == .waiting else {
            return
        }
        state = .migrating
        migrator.registerMigration("cache-v1") { db in
            try db.create(table: Station.databaseTableName) { t in
                t.primaryKey(Station.Columns.code.name, .text)
                t.column(Station.Columns.name.name, .text)
                t.column(Station.Columns.tz.name, .text)
                t.column(Station.Columns.lat.name, .real)
                t.column(Station.Columns.lon.name, .real)
                t.column(Station.Columns.address1.name, .text)
                t.column(Station.Columns.address2.name, .text)
                t.column(Station.Columns.city.name, .text)
                t.column(Station.Columns.zip.name, .text)
                t.column(Station.Columns.formattedPostalAddress.name, .text)
                t.column(Station.Columns.trainIdentifiers.name, .text).notNull()
                t.column(Station.Columns.normalizedCode.name, .text)
                t.column(Station.Columns.normalizedName.name, .text)
                t.column(Station.Columns.normalizedCity.name, .text)
            }
            try db.create(table: Train.databaseTableName) { t in
                t.primaryKey(Train.Columns.trainID.name, .text)
                t.column(Train.Columns.routeName.name, .text)
                t.column(Train.Columns.trainNum.name, .text).notNull()
                t.column(Train.Columns.trainNumRaw.name, .text).notNull()
                t.column(Train.Columns.lat.name, .real)
                t.column(Train.Columns.lon.name, .real)
                t.column(Train.Columns.iconColor.name, .text)
                t.column(Train.Columns.heading.name, .text)
                t.column(Train.Columns.eventCode.name, .text)
                t.column(Train.Columns.eventTZ.name, .text)
                t.column(Train.Columns.eventName.name, .text)
                t.column(Train.Columns.origCode.name, .text)
                t.column(Train.Columns.originTZ.name, .text)
                t.column(Train.Columns.origName.name, .text)
                t.column(Train.Columns.destCode.name, .text)
                t.column(Train.Columns.destTZ.name, .text)
                t.column(Train.Columns.destName.name, .text)
                t.column(Train.Columns.trainState.name, .text)
                t.column(Train.Columns.velocity.name, .real)
                t.column(Train.Columns.statusMsg.name, .text)
                t.column(Train.Columns.createdAt.name, .datetime).notNull()
                t.column(Train.Columns.updatedAt.name, .datetime).notNull()
                t.column(Train.Columns.lastValTS.name, .datetime).notNull()
                t.column(Train.Columns.objectID.name, .integer)
                t.column(Train.Columns.provider.name, .text)
                t.column(Train.Columns.providerShort.name, .text)
                t.column(Train.Columns.onlyOfTrainNum.name, .boolean)
                t.column(Train.Columns.alerts.name, .blob).notNull()
            }
            try db.create(table: StopRecord.databaseTableName) { t in
                t.column(StopRecord.Columns.trainID.name, .text).notNull()
                    .references(Train.databaseTableName, onDelete: .cascade)
                t.column(StopRecord.Columns.stationCode.name, .text).notNull()
                t.column(StopRecord.Columns.schArr.name, .datetime).notNull()
                t.column(StopRecord.Columns.schDep.name, .datetime).notNull()
                t.column(StopRecord.Columns.arr.name, .datetime)
                t.column(StopRecord.Columns.dep.name, .datetime)
                t.column(StopRecord.Columns.platform.name, .text)
                t.column(StopRecord.Columns.status.name, .text)
                t.primaryKey([StopRecord.Columns.trainID.name, StopRecord.Columns.stationCode.name])
            }
        }
        try migrator.migrate(pool)
        state = .done
    }
}

///
actor UserDataMigrator: Migrator {
    private var state = MigrationState.waiting
    private var migrator: DatabaseMigrator = .init()
    ///
    func runMigrations(_ pool: DatabasePool) throws {
        guard state == .waiting else {
            return
        }
        state = .migrating
        migrator.registerMigration("userdata-v1") { db in
            try db.create(table: StationUserData.databaseTableName) { t in
                t.primaryKey(StationUserData.Columns.code.name, .text)
                t.column(StationUserData.Columns.isFavorite.name, .boolean)
            }
        }
        try migrator.migrate(pool)
        state = .done
    }
}
