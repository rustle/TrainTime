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
#if USE_COLLECTION_VIEW
            StationListCollectionView()
                .environment(\.client, ClientKey.defaultValue)
#else
            StationList()
                .environment(\.client, ClientKey.defaultValue)
#endif // USE_COLLECTION_VIEW
                
        }
    }
}
