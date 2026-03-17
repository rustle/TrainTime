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
            try db.create(table: TTStation.databaseTableName) { t in
                t.primaryKey(TTStation.Columns.code.name, .text)
                t.column(TTStation.Columns.name.name, .text)
                t.column(TTStation.Columns.tz.name, .text)
                t.column(TTStation.Columns.lat.name, .real)
                t.column(TTStation.Columns.lon.name, .real)
                t.column(TTStation.Columns.address1.name, .text)
                t.column(TTStation.Columns.address2.name, .text)
                t.column(TTStation.Columns.city.name, .text)
                t.column(TTStation.Columns.zip.name, .text)
                t.column(TTStation.Columns.formattedPostalAddress.name, .text)
                t.column(TTStation.Columns.trainIdentifiers.name, .text).notNull()
                t.column(TTStation.Columns.normalizedCode.name, .text)
                t.column(TTStation.Columns.normalizedName.name, .text)
                t.column(TTStation.Columns.normalizedCity.name, .text)
                t.column(TTStation.Columns.isFavorite.name, .boolean)
            }
            try db.create(table: TTTrain.databaseTableName) { t in
                t.primaryKey(TTTrain.Columns.trainID.name, .text)
                t.column(TTTrain.Columns.routeName.name, .text)
                t.column(TTTrain.Columns.trainNum.name, .text).notNull()
                t.column(TTTrain.Columns.trainNumRaw.name, .text).notNull()
                t.column(TTTrain.Columns.lat.name, .real)
                t.column(TTTrain.Columns.lon.name, .real)
                t.column(TTTrain.Columns.iconColor.name, .text)
                t.column(TTTrain.Columns.heading.name, .text)
                t.column(TTTrain.Columns.eventCode.name, .text)
                t.column(TTTrain.Columns.eventTZ.name, .text)
                t.column(TTTrain.Columns.eventName.name, .text)
                t.column(TTTrain.Columns.origCode.name, .text)
                t.column(TTTrain.Columns.originTZ.name, .text)
                t.column(TTTrain.Columns.origName.name, .text)
                t.column(TTTrain.Columns.destCode.name, .text)
                t.column(TTTrain.Columns.destTZ.name, .text)
                t.column(TTTrain.Columns.destName.name, .text)
                t.column(TTTrain.Columns.trainState.name, .text)
                t.column(TTTrain.Columns.velocity.name, .real)
                t.column(TTTrain.Columns.statusMsg.name, .text)
                t.column(TTTrain.Columns.createdAt.name, .datetime).notNull()
                t.column(TTTrain.Columns.updatedAt.name, .datetime).notNull()
                t.column(TTTrain.Columns.lastValTS.name, .datetime).notNull()
                t.column(TTTrain.Columns.objectID.name, .integer)
                t.column(TTTrain.Columns.provider.name, .text)
                t.column(TTTrain.Columns.providerShort.name, .text)
                t.column(TTTrain.Columns.onlyOfTrainNum.name, .boolean)
                t.column(TTTrain.Columns.alerts.name, .blob).notNull()
            }
            try db.create(table: StopRecord.databaseTableName) { t in
                t.column(StopRecord.Columns.trainID.name, .text).notNull()
                    .references(TTTrain.databaseTableName, onDelete: .cascade)
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
