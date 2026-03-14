import Amtrak
import Foundation

///
typealias StopStatus = StationStatus

///
struct Stop: Codable, Sendable, Equatable, CustomDebugStringConvertible {
    /// Station code
    let code: String
    /// Scheduled arrival time
    let schArr: Date
    /// Scheduled departure time
    let schDep: Date
    /// Actual arrival time
    let arr: Date?
    /// Actual departure time
    let dep: Date?
    /// Platform name/number, if available
    let platform: String?
    /// One of "Enroute", "Station", "Departed", or "Unknown"
    let status: StopStatus?
    ///
    var debugDescription: String {
        JSONEncoder.jsonDebugDescription(for: self) ?? "Stop"
    }
    ///
    init(code: String,
         tz: String? = nil,
         bus: Bool? = nil,
         schArr: Date,
         schDep: Date,
         arr: Date? = nil,
         dep: Date? = nil,
         platform: String? = nil,
         status: StopStatus? = nil) {
        self.code = code
        self.schArr = schArr
        self.schDep = schDep
        self.arr = arr
        self.dep = dep
        self.platform = platform
        self.status = status
    }
    ///
    init(station: Station) {
        code = station.code
        schArr = station.schArr
        schDep = station.schDep
        arr = station.arr
        dep = station.dep
        platform = station.platform
        status = station.status
    }
}
