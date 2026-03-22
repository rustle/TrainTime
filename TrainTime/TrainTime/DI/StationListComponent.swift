import GRDB

protocol StationListDependency: Sendable {
    var stationsService: StationsService { get }
    var logExportService: LogExportService { get }
    func makeStationComponent() -> StationComponent
}

struct StationListComponent: StationListDependency {
    let stationsService: StationsService
    let logExportService: LogExportService
    private let _makeStationComponent: @Sendable () -> StationComponent
    func makeStationComponent() -> StationComponent {
        _makeStationComponent()
    }
    init (stationsService: StationsService,
          logExportService: LogExportService,
          makeStationComponent: @Sendable @escaping () -> StationComponent) {
        self.stationsService = stationsService
        self.logExportService = logExportService
        _makeStationComponent = makeStationComponent
    }
}
