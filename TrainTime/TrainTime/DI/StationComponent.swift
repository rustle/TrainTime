import Foundation
import GRDB

protocol StationDependency: Sendable {
    var stationService: StationService { get }
    var trainService: TrainService { get }
    /// The calendar the station's schedule is grouped and labelled with.
    var calendar: Calendar { get }
}

struct StationComponent: StationDependency {
    let stationService: StationService
    let trainService: TrainService
    let calendar: Calendar
}
