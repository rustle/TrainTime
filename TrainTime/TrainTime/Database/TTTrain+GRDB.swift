import Amtrak
import Foundation
import GRDB

extension TTTrain: TableRecord {
    static let databaseTableName = "train"
}

extension TTTrain: FetchableRecord {
    /// Fetches the train's scalar fields. Stops must be loaded separately via StopRecord.
    init(row: Row) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        routeName = row["routeName"]
        trainNum = row["trainNum"]
        trainNumRaw = row["trainNumRaw"]
        trainID = row["trainID"]
        lat = row["lat"]
        lon = row["lon"]
        iconColor = row["iconColor"]
        heading = try (row["heading"] as Data?).map { try decoder.decode(Heading.self, from: $0) }
        eventCode = row["eventCode"]
        eventTZ = row["eventTZ"]
        eventName = row["eventName"]
        origCode = row["origCode"]
        originTZ = row["originTZ"]
        origName = row["origName"]
        destCode = row["destCode"]
        destTZ = row["destTZ"]
        destName = row["destName"]
        trainState = try (row["trainState"] as Data?).map { try decoder.decode(TrainState.self, from: $0) }
        velocity = row["velocity"]
        statusMsg = row["statusMsg"]
        createdAt = Date(timeIntervalSince1970: row["createdAt"])
        updatedAt = Date(timeIntervalSince1970: row["updatedAt"])
        lastValTS = Date(timeIntervalSince1970: row["lastValTS"])
        objectID = row["objectID"]
        provider = row["provider"]
        providerShort = row["providerShort"]
        onlyOfTrainNum = row["onlyOfTrainNum"]
        alerts = try decoder.decode([TrainAlert].self, from: row["alerts"])
        stops = [:]
    }
}

extension TTTrain: PersistableRecord {
    /// Persists the train's scalar fields. Stops must be saved separately via StopRecord.
    func encode(to container: inout PersistenceContainer) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        container["trainID"] = trainID
        container["routeName"] = routeName
        container["trainNum"] = trainNum
        container["trainNumRaw"] = trainNumRaw
        container["lat"] = lat
        container["lon"] = lon
        container["iconColor"] = iconColor
        container["heading"] = try heading.map { try encoder.encode($0) }
        container["eventCode"] = eventCode
        container["eventTZ"] = eventTZ
        container["eventName"] = eventName
        container["origCode"] = origCode
        container["originTZ"] = originTZ
        container["origName"] = origName
        container["destCode"] = destCode
        container["destTZ"] = destTZ
        container["destName"] = destName
        container["trainState"] = try trainState.map { try encoder.encode($0) }
        container["velocity"] = velocity
        container["statusMsg"] = statusMsg
        container["createdAt"] = createdAt.timeIntervalSince1970
        container["updatedAt"] = updatedAt.timeIntervalSince1970
        container["lastValTS"] = lastValTS.timeIntervalSince1970
        container["objectID"] = objectID
        container["provider"] = provider
        container["providerShort"] = providerShort
        container["onlyOfTrainNum"] = onlyOfTrainNum
        container["alerts"] = try encoder.encode(alerts)
    }
}
