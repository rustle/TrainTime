import GRDB

protocol AppDependency: Sendable {
    var client: TTClient { get }
    var databaseConnection: DatabasePool { get }
    func makeStationListComponent() -> StationListComponent
}

struct AppComponent: AppDependency {
    let client: TTClient
    let database: Database
    let databaseConnection: DatabasePool
    func makeStationListComponent() -> StationListComponent {
        StationListComponent(client: client,
                             service: .init(client: client,
                                            databaseConnection: databaseConnection))
    }
    init(database: Database,
         databaseConnection: DatabasePool) {
        self.client = TTClient()
        self.database = database
        self.databaseConnection = databaseConnection
    }
}
