import GRDB

protocol StationListDependency: Sendable {
    var client: TTClient { get }
    var service: StationsService { get }
    func makeStationComponent() -> StationComponent
}

struct StationListComponent: StationListDependency {
#if DEBUG
    struct PreviewDatabase: WriteStationsProvider, StationsStreamProvider {
        var stations: any AsyncSequence<[TTStation], any Error> {
            _stations
        }
        func writeStations(_ stations: [TTStation]) async throws {
            continuation.yield(stations.sorted { lhs, rhs in
                (lhs.normalizedName ?? lhs.normalizedCode) < (rhs.normalizedName ?? rhs.normalizedCode)
            })
        }
        private let _stations: AsyncThrowingStream<[TTStation], any Error>
        let continuation: AsyncThrowingStream<[TTStation], any Error>.Continuation
        init() {
            let (stations, continuation) = AsyncThrowingStream<[TTStation], any Error>.makeStream()
            _stations = stations
            self.continuation = continuation
        }
    }
    static func previewComponent() -> Self {
        let previewClient = TTClient()
        let previewDatabase = PreviewDatabase()
        let service = StationsService(
            fetchAllStationsProvider: previewClient,
            writeStationsProvider: previewDatabase,
            stationsStreamProvider: previewDatabase
        )
        return StationListComponent(client: previewClient,
                                    service: service)
    }
#endif // DEBUG
    let client: TTClient
    let service: StationsService
    func makeStationComponent() -> StationComponent {
        StationComponent(client: self.client)
    }
}
