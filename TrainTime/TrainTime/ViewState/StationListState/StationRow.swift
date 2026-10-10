import Foundation
import Observation

@Observable
final class StationRow: Identifiable, Comparable, Hashable, Sendable, CustomDebugStringConvertible {
    // MARK: - Sorting
    static func == (lhs: StationRow,
                    rhs: StationRow) -> Bool {
        lhs.station == rhs.station
    }
    static func < (lhs: StationRow,
                   rhs: StationRow) -> Bool {
        lhs.title < rhs.title
    }
    // MARK: - Data
    let id: String
    let title: String
    let station: Station
    // MARK: - Search
    let searchDocument: StationSearch.Document
    // MARK: - Debugging
    var debugDescription: String {
        station.debugDescription
    }
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(station)
    }
    // MARK: - Init
    init(station: Station) {
        title = station.name ?? station.code
        id = station.code + station.trainIdentifiers.joined()
        self.station = station
        searchDocument = StationSearch.Document(station: station)
    }
}

extension StationRow {
    func normalizedTitle() -> String {
        station.normalizedName ?? station.normalizedCode
    }
}
