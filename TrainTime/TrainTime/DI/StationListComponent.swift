import GRDB

protocol StationListDependency: Sendable {
    var stationsService: StationsService { get }
    func makeStationComponent() -> StationComponent
}

struct StationListComponent: StationListDependency {
    let stationsService: StationsService
    private let _makeStationComponent: @Sendable () -> StationComponent
    func makeStationComponent() -> StationComponent {
        _makeStationComponent()
    }
    init (stationsService: StationsService,
          makeStationComponent: @Sendable @escaping () -> StationComponent) {
        self.stationsService = stationsService
        _makeStationComponent = makeStationComponent
    }
}
