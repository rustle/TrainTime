import SwiftUI

@main
struct TrainTimeApp: App {
    @State var appComponent: AppComponent?
    @State var stationListComponent: StationListComponent?
    private func setup() async {
        do {
            let appComponent = try await AppComponent.makeProductionAppComponent()
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
