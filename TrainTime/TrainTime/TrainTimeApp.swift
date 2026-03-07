import SwiftUI

struct ClientKey: EnvironmentKey {
    static let defaultValue: TTClient = .init()
}

extension EnvironmentValues {
    var client: TTClient {
        get { self[ClientKey.self] }
        set { self[ClientKey.self] = newValue }
    }
}

@main
struct TrainTimeApp: App {
    var body: some Scene {
        WindowGroup {
            StationList()
                .environment(\.client, ClientKey.defaultValue)
        }
    }
}
