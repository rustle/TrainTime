import Amtrak
import Contacts
import CoreLocation
import Foundation
import GRDB
import Observation

///
struct Station: Codable, Equatable, Hashable, Sendable, CustomDebugStringConvertible {
    private static func formattedPostalAddress(
        address1: String?,
        address2: String?,
        city: String?,
        zip: String?
    ) -> String {
        let postalAddress = CNMutablePostalAddress()
        let addressLines = [address1, address2].compactMap { $0 }
        if !addressLines.isEmpty {
            postalAddress.street = addressLines.joined(separator: "\n")
        }
        if let city {
            postalAddress.city = city
        }
        if let zip {
            postalAddress.postalCode = zip
        }
        let formatter = CNPostalAddressFormatter()
        return formatter.string(from: postalAddress)
    }
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
    var location: CLLocation? {
        guard let lat, let lon else {
            return nil
        }
        return .init(latitude: lat,
                     longitude: lon)
    }
    ///
    let formattedPostalAddress: String
    // MARK: - Search
    ///
    let normalizedCode: String
    ///
    let normalizedName: String?
    ///
    let normalizedCity: String?
    // MARK: - User data
    ///
    var isFavorite: Bool?
    // MARK: - Debugging
    ///
    var debugDescription: String {
        JSONEncoder.jsonDebugDescription(for: self) ?? "Station"
    }
    // MARK: - Init
    /// init for #preview
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
        normalizedCode = code.normalized
        normalizedName = name?.normalized
        normalizedCity = city?.normalized
        isFavorite = nil
        formattedPostalAddress = Self.formattedPostalAddress(address1: address1,
                                                             address2: address2,
                                                             city: city,
                                                             zip: zip)
    }
    /// init for mapping from Amtrak.StationMetadata
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
        normalizedCode = code.normalized
        normalizedName = name?.normalized
        normalizedCity = city?.normalized
        isFavorite = nil
        formattedPostalAddress = Self.formattedPostalAddress(address1: address1,
                                                             address2: address2,
                                                             city: city,
                                                             zip: zip)
    }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self,
                                                  forKey: .name)
        self.code = try container.decode(String.self,
                                         forKey: .code)
        self.tz = try container.decodeIfPresent(String.self,
                                                forKey: .tz)
        self.lat = try container.decodeIfPresent(Double.self,
                                                 forKey: .lat)
        self.lon = try container.decodeIfPresent(Double.self,
                                                 forKey: .lon)
        self.address1 = try container.decodeIfPresent(String.self,
                                                      forKey: .address1)
        self.address2 = try container.decodeIfPresent(String.self,
                                                      forKey: .address2)
        self.city = try container.decodeIfPresent(String.self,
                                                  forKey: .city)
        self.zip = try container.decodeIfPresent(String.self,
                                                 forKey: .zip)
        self.trainIdentifiers = try container.decode([String].self,
                                                     forKey: .trainIdentifiers)
        normalizedCode = code.normalized
        normalizedName = name?.normalized
        normalizedCity = city?.normalized
        isFavorite = nil
        formattedPostalAddress = Self.formattedPostalAddress(address1: address1,
                                                             address2: address2,
                                                             city: city,
                                                             zip: zip)
    }
}
