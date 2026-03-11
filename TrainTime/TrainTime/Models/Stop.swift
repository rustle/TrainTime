import Amtrak
import Foundation

///
typealias StopStatus = StationStatus

///
struct Stop: Codable, Sendable, Equatable, CustomDebugStringConvertible {
    /// Scheduled arrival time
    public let schArr: Date
    /// Scheduled departure time
    public let schDep: Date
    /// Actual arrival time
    public let arr: Date?
    /// Actual departure time
    public let dep: Date?
    /// Platform name/number, if available
    public let platform: String?
    /// One of "Enroute", "Station", "Departed", or "Unknown"
    public let status: StopStatus?
    ///
    var debugDescription: String {
        JSONEncoder.jsonDebugDescription(for: self) ?? "Stop"
    }
    ///
    public init(name: String,
                code: String,
                tz: String? = nil,
                bus: Bool? = nil,
                schArr: Date,
                schDep: Date,
                arr: Date? = nil,
                dep: Date? = nil,
                platform: String? = nil,
                status: StopStatus? = nil) {
        self.schArr = schArr
        self.schDep = schDep
        self.arr = arr
        self.dep = dep
        self.platform = platform
        self.status = status
    }
    ///
    init(station: Station) {
        schArr = station.schArr
        schDep = station.schDep
        arr = station.arr
        dep = station.dep
        platform = station.platform
        status = station.status
    }
}
