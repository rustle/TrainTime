import Amtrak
import Foundation
import Observation

///
struct TTStation: Codable, Equatable, Sendable, CustomDebugStringConvertible {
    ///
    let name: String?
    ///
    let code: String
    ///
    let tz: String?
    ///
    let lat: Double?
    ///
    let lon: Double?
    ///
    let address1: String?
    ///
    let address2: String?
    ///
    let city: String?
    ///
    let zip: String?
    ///
    let trainIdentifiers: [String]
    ///
    var debugDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self),
            let string = String(data: data,
                                encoding: .utf8) {
            return string
        }
        return "Train"
    }
    ///
    init(name: String? = nil,
         code: String,
         tz: String? = nil,
         lat: Double? = nil,
         lon: Double? = nil,
         address1: String? = nil,
         address2: String? = nil,
         city: String? = nil,
         zip: String? = nil,
         trainIdentifiers: [String]) {
        self.name = name
        self.code = code
        self.tz = tz
        self.lat = lat
        self.lon = lon
        self.address1 = address1
        self.address2 = address2
        self.city = city
        self.zip = zip
        self.trainIdentifiers = trainIdentifiers
    }
    ///
    init(stationMetadata: StationMetadata) {
        name = stationMetadata.name
        code = stationMetadata.code
        tz = stationMetadata.tz
        lat = stationMetadata.lat
        lon = stationMetadata.lon
        address1 = stationMetadata.address1
        address2 = stationMetadata.address2
        city = stationMetadata.city
        zip = stationMetadata.zip
        trainIdentifiers = stationMetadata.trains
    }
}

typealias TTStationResponse = [String: TTStation]
