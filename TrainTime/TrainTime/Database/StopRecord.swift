import Foundation
import GRDB

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

extension StopRecord: TableRecord {
    static let databaseTableName = "stop"
}

extension StopRecord: FetchableRecord {
    init(row: Row) throws {
        trainID = row["trainID"]
        stationCode = row["stationCode"]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        stop = Stop(
            name: "",
            code: row["stationCode"],
            schArr: Date(timeIntervalSince1970: row["schArr"]),
            schDep: Date(timeIntervalSince1970: row["schDep"]),
            arr: (row["arr"] as Double?).map { Date(timeIntervalSince1970: $0) },
            dep: (row["dep"] as Double?).map { Date(timeIntervalSince1970: $0) },
            platform: row["platform"],
            status: try (row["status"] as Data?).map { try decoder.decode(StopStatus.self, from: $0) }
        )
    }
}

extension StopRecord: PersistableRecord {
    func encode(to container: inout PersistenceContainer) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        container["trainID"] = trainID
        container["stationCode"] = stationCode
        container["schArr"] = stop.schArr.timeIntervalSince1970
        container["schDep"] = stop.schDep.timeIntervalSince1970
        container["arr"] = stop.arr?.timeIntervalSince1970
        container["dep"] = stop.dep?.timeIntervalSince1970
        container["platform"] = stop.platform
        container["status"] = try stop.status.map { try encoder.encode($0) }
    }
}
