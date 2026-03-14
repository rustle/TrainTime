import GRDB

protocol StationDependency: Sendable {
    var stationService: StationService { get }
    var trainService: TrainService { get }
}

struct StationComponent: StationDependency {
    let stationService: StationService
    let trainService: TrainService
}
