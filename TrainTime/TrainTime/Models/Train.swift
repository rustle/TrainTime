import Amtrak
import Foundation
import GRDB

///
struct Train: Codable, Sendable, Equatable, CustomDebugStringConvertible {
    /// Name of the train route
    let routeName: String?
    /// Train number
    let trainNum: String
    /// Train number, minus any prefix (ie v for via rail and b for brightline)
    let trainNumRaw: String
    /// Train ID
    let trainID: String
    /// Latitude of the train
    let lat: Double?
    /// Longitude of the train
    let lon: Double?
    /// Calculated icon color for the frontend
    let iconColor: String?
    /// Direction the train is heading in the 8 cardinal directions/
    let heading: Heading?
    /// Upcoming/current station
    let eventCode: String?
    /// Timezone of the upcoming/current station
    let eventTZ: String?
    /// Name of the upcoming/current station
    let eventName: String?
    /// Origin station code
    let origCode: String?
    /// Timezone of the origin station
    let originTZ: String?
    /// Name of the origin station
    let origName: String?
    /// Destination station code
    let destCode: String?
    /// Timezone of the destination station
    let destTZ: String?
    /// Name of the destination station
    let destName: String?
    /// Either "Predeparture", "Active", or "Complete"
    let trainState: TrainState?
    /// Speed of the train in MPH
    let velocity: Double?
    /// Status message associated with the train, if any
    let statusMsg: String?
    /// Timestamp of when the train data was stored in Amtrak's DB
    let createdAt: Date
    /// Timestamp of when the train data was last updated
    let updatedAt: Date
    /// Timestamp of when the train data was last received
    let lastValTS: Date
    /// ID of the train data in Amtrak's DB
    let objectID: Int?
    /// The provider of this train, either "Amtrak", "Via", or "Brightline"
    let provider: String?
    /// A shortened version of `provider`, 4 or less characters, either "AMTK", "VIA", or "BLNE"
    let providerShort: String?
    /// If this is the only train with its number (IE if there is only a single 3 active)
    let onlyOfTrainNum: Bool?
    /// Array of alerts
    let alerts: [TrainAlert]
    ///
    var debugDescription: String {
        JSONEncoder.jsonDebugDescription(for: self) ??  "Train"
    }
    ///
    init(routeName: String? = nil,
         trainNum: String,
         trainNumRaw: String,
         trainID: String,
         lat: Double? = nil,
         lon: Double? = nil,
         iconColor: String? = nil,
         heading: Heading? = nil,
         eventCode: String? = nil,
         eventTZ: String? = nil,
         eventName: String? = nil,
         origCode: String? = nil,
         originTZ: String? = nil,
         origName: String? = nil,
         destCode: String? = nil,
         destTZ: String? = nil,
         destName: String? = nil,
         trainState: TrainState? = nil,
         velocity: Double? = nil,
         statusMsg: String? = nil,
         createdAt: Date,
         updatedAt: Date,
         lastValTS: Date,
         objectID: Int? = nil,
         provider: String? = nil,
         providerShort: String? = nil,
         onlyOfTrainNum: Bool? = nil,
         alerts: [TrainAlert] = []) {
        self.routeName = routeName
        self.trainNum = trainNum
        self.trainNumRaw = trainNumRaw
        self.trainID = trainID
        self.lat = lat
        self.lon = lon
        self.iconColor = iconColor
        self.heading = heading
        self.eventCode = eventCode
        self.eventTZ = eventTZ
        self.eventName = eventName
        self.origCode = origCode
        self.originTZ = originTZ
        self.origName = origName
        self.destCode = destCode
        self.destTZ = destTZ
        self.destName = destName
        self.trainState = trainState
        self.velocity = velocity
        self.statusMsg = statusMsg
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastValTS = lastValTS
        self.objectID = objectID
        self.provider = provider
        self.providerShort = providerShort
        self.onlyOfTrainNum = onlyOfTrainNum
        self.alerts = alerts
    }
    init(train: Amtrak.Train) {
        routeName = train.routeName
        trainNum = train.trainNum
        trainNumRaw = train.trainNumRaw
        trainID = train.trainID
        lat = train.lat
        lon = train.lon
        iconColor = train.iconColor
        heading = train.heading
        eventCode = train.eventCode
        eventTZ = train.eventTZ
        eventName = train.eventName
        origCode = train.origCode
        originTZ = train.originTZ
        origName = train.origName
        destCode = train.destCode
        destTZ = train.destTZ
        destName = train.destName
        trainState = train.trainState
        velocity = train.velocity
        statusMsg = train.statusMsg
        createdAt = train.createdAt
        updatedAt = train.updatedAt
        lastValTS = train.lastValTS
        objectID = train.objectID
        provider = train.provider
        providerShort = train.providerShort
        onlyOfTrainNum = train.onlyOfTrainNum
        alerts = train.alerts
    }
}
