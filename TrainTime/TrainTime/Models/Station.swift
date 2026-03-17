import Amtrak
import Contacts
import CoreLocation
import Foundation
import GRDB
import Observation

///
struct TTStation: Codable, Equatable, Hashable, Sendable, CustomDebugStringConvertible {
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
    var location: CLLocation? {
        guard let lat, let lon else {
            return nil
        }
        return .init(latitude: lat,
                     longitude: lon)
    }
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
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        normalizedCode = code.folding(options: options,
                                      locale: .current)
        normalizedName = name?.folding(options: options,
                                       locale: .current)
        normalizedCity = city?.folding(options: options,
                                       locale: .current)
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
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        normalizedCode = stationMetadata.code.folding(options: options,
                                                      locale: .current)
        normalizedName = stationMetadata.name?.folding(options: options,
                                                       locale: .current)
        normalizedCity = stationMetadata.city?.folding(options: options,
                                                       locale: .current)
        isFavorite = nil
        formattedPostalAddress = Self.formattedPostalAddress(address1: address1,
                                                             address2: address2,
                                                             city: city,
                                                             zip: zip)
    }
}

typealias TTStationResponse = [String: TTStation]
