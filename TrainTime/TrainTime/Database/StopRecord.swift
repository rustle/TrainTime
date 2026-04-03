import Foundation
import GRDB

extension StopRecord: TableRecord {
    static let databaseTableName = "stop"
    enum Columns {
        static let trainID = Column("trainID")
        static let stationCode = Column("stationCode")
        static let schArr = Column("schArr")
        static let schDep = Column("schDep")
        static let arr = Column("arr")
        static let dep = Column("dep")
        static let platform = Column("platform")
        static let status = Column("status")
    }
}

/// GRDB record for the `stop` table, pairing a `Stop` value with its
/// train and station identifiers.
struct StopRecord {
    let trainID: String
    let stationCode: String
    let stop: Stop

    init(trainID: String, stationCode: String, stop: Stop) {
        self.trainID = trainID
        self.stationCode = stationCode
        self.stop = stop
    }
}

extension Stop: FetchableRecord {
    init(row: Row) throws {
        code = row[StopRecord.Columns.stationCode]
        schArr = row[StopRecord.Columns.schArr]
        schDep = row[StopRecord.Columns.schDep]
        arr = row[StopRecord.Columns.arr]
        dep = row[StopRecord.Columns.dep]
        platform = row[StopRecord.Columns.platform]
        status = row[StopRecord.Columns.status]
    }
}

extension StopRecord: FetchableRecord {
    init(row: Row) throws {
        trainID = row[Columns.trainID]
        stationCode = row[Columns.stationCode]
        stop = try Stop(row: row)
    }
}

extension StopRecord: PersistableRecord {
    func encode(to container: inout PersistenceContainer) throws {
        container["trainID"] = trainID
        container["stationCode"] = stationCode
        container["schArr"] = stop.schArr
        container["schDep"] = stop.schDep
        container["arr"] = stop.arr
        container["dep"] = stop.dep
        container["platform"] = stop.platform
        container["status"] = stop.status
    }
}
