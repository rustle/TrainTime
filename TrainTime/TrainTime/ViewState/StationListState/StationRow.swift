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
    let station: TTStation
    // MARK: - Debugging
    var debugDescription: String {
        station.debugDescription
    }
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(station)
    }
    // MARK: - Init
    init(station: TTStation) {
        title = station.name ?? station.code
        id = station.code + station.trainIdentifiers.joined()
        self.station = station
    }
}

extension Array where Element == StationRow {
    func search(query: String) -> Self {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var exactCode: [StationRow] = []
        var codePrefix: [StationRow] = []
        var namePrefix: [StationRow] = []
        var nameContains: [StationRow] = []
        var cityContains: [StationRow] = []
        for row in self {
            if row.station.normalizedCode == normalizedQuery {
                exactCode.sortedInsert(row)
            } else if row.station.normalizedCode.hasPrefix(normalizedQuery) {
                codePrefix.sortedInsert(row)
            } else if let name = row.station.normalizedName {
                if name.hasPrefix(normalizedQuery) {
                    namePrefix.sortedInsert(row)
                } else if name.contains(normalizedQuery) {
                    nameContains.sortedInsert(row)
                } else if let city = row.station.normalizedCity, city.contains(normalizedQuery) {
                    cityContains.sortedInsert(row)
                }
            } else if let city = row.station.normalizedCity, city.contains(normalizedQuery) {
                cityContains.sortedInsert(row)
            }
        }
        return exactCode + codePrefix + namePrefix + nameContains + cityContains
    }
}

extension StationRow {
    func normalizedTitle() -> String {
        station.normalizedName ?? station.normalizedCode
    }
}
