import GRDB

protocol StationDependency: Sendable {
    var client: TTClient { get }
}

struct StationComponent: StationDependency {
    let client: TTClient
}
