import SwiftUI

@main
struct TrainTimeApp: App {
    @State var appComponent: AppComponent?
    @State var stationListComponent: StationListComponent?
    private func setup() async {
        do {
            let database = Database(name: "train.db")
            let connection = try database.newConnection()
            try await database.runMigrations(connection)
            let appComponent = AppComponent(database: database,
                                            databaseConnection: connection)
            self.appComponent = appComponent
            self.stationListComponent = appComponent.makeStationListComponent()
        } catch {
            // TODO: Retry logic
        }
    }
    var body: some Scene {
        WindowGroup {
            if let stationListComponent {
                StationList(component: stationListComponent)
            } else {
                Group {
                    ProgressView()
                }
                    .task {
                        await setup()
                    }
            }
        }
    }
}
