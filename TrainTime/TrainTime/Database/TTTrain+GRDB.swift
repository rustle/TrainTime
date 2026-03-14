import Amtrak
import Foundation
import GRDB

extension TTTrain: TableRecord {
    static let databaseTableName = "train"
    enum Columns {
        static let trainID = Column("trainID")
        static let routeName = Column("routeName")
        static let trainNum = Column("trainNum")
        static let trainNumRaw = Column("trainNumRaw")
        static let lat = Column("lat")
        static let lon = Column("lon")
        static let iconColor = Column("iconColor")
        static let heading = Column("heading")
        static let eventCode = Column("eventCode")
        static let eventTZ = Column("eventTZ")
        static let eventName = Column("eventName")
        static let origCode = Column("origCode")
        static let originTZ = Column("originTZ")
        static let origName = Column("origName")
        static let destCode = Column("destCode")
        static let destTZ = Column("destTZ")
        static let destName = Column("destName")
        static let trainState = Column("trainState")
        static let velocity = Column("velocity")
        static let statusMsg = Column("statusMsg")
        static let createdAt = Column("createdAt")
        static let updatedAt = Column("updatedAt")
        static let lastValTS = Column("lastValTS")
        static let objectID = Column("objectID")
        static let provider = Column("provider")
        static let providerShort = Column("providerShort")
        static let onlyOfTrainNum = Column("onlyOfTrainNum")
        static let alerts = Column("alerts")
    }
}

extension TTTrain {
    static let stopRecords = hasMany(StopRecord.self, using: ForeignKey(["trainID"]))
}

extension TTTrain: Identifiable {
    var id: String {
        trainID
    }
}

extension TTTrain: FetchableRecord {
    /// Fetches the train's scalar fields. Stops must be loaded separately via StopRecord.
    init(row: Row) throws {
        routeName = row[Columns.routeName]
        trainNum = row[Columns.trainNum]
        trainNumRaw = row[Columns.trainNumRaw]
        trainID = row[Columns.trainID]
        lat = row[Columns.lat]
        lon = row[Columns.lon]
        iconColor = row[Columns.iconColor]
        heading = row[Columns.heading]
        eventCode = row[Columns.eventCode]
        eventTZ = row[Columns.eventTZ]
        eventName = row[Columns.eventName]
        origCode = row[Columns.origCode]
        originTZ = row[Columns.originTZ]
        origName = row[Columns.origName]
        destCode = row[Columns.destCode]
        destTZ = row[Columns.destTZ]
        destName = row[Columns.destName]
        trainState = row[Columns.trainState]
        velocity = row[Columns.velocity]
        statusMsg = row[Columns.statusMsg]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
        lastValTS = row[Columns.lastValTS]
        objectID = row[Columns.objectID]
        provider = row[Columns.provider]
        providerShort = row[Columns.providerShort]
        onlyOfTrainNum = row[Columns.onlyOfTrainNum]
        alerts = try JSONDecoder().decode([TrainAlert].self, from: row[Columns.alerts])
        stops = [:]
    }
}

extension TTTrain: PersistableRecord {
    /// Persists the train's scalar fields. Stops must be saved separately via StopRecord.
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.trainID] = trainID
        container[Columns.routeName] = routeName
        container[Columns.trainNum] = trainNum
        container[Columns.trainNumRaw] = trainNumRaw
        container[Columns.lat] = lat
        container[Columns.lon] = lon
        container[Columns.iconColor] = iconColor
        container[Columns.heading] = heading
        container[Columns.eventCode] = eventCode
        container[Columns.eventTZ] = eventTZ
        container[Columns.eventName] = eventName
        container[Columns.origCode] = origCode
        container[Columns.originTZ] = originTZ
        container[Columns.origName] = origName
        container[Columns.destCode] = destCode
        container[Columns.destTZ] = destTZ
        container[Columns.destName] = destName
        container[Columns.trainState] = trainState
        container[Columns.velocity] = velocity
        container[Columns.statusMsg] = statusMsg
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
        container[Columns.lastValTS] = lastValTS
        container[Columns.objectID] = objectID
        container[Columns.provider] = provider
        container[Columns.providerShort] = providerShort
        container[Columns.onlyOfTrainNum] = onlyOfTrainNum
        container[Columns.alerts] = try JSONEncoder().encode(alerts)
    }
}
