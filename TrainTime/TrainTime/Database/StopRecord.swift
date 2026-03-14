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

extension StopRecord: FetchableRecord {
    init(row: Row) throws {
        trainID = row["trainID"]
        stationCode = row["stationCode"]
        stop = Stop(
            code: row["stationCode"],
            schArr: row["schArr"],
            schDep: row["schDep"],
            arr: row["arr"],
            dep: row["dep"],
            platform: row["platform"],
            status: row["status"]
        )
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
