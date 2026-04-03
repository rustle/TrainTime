import Amtrak

final class APIService: Sendable {
    private let client = AmtrakClient()
    func fetchStations() async throws -> [Station] {
        try await client.fetchAllStations().values.map(Station.init(stationMetadata:))
    }
    func fetchStation(code: String) async throws -> Station {
        Station(stationMetadata: try await client.fetchStation(id: code))
    }
    func fetchTrain(identifier: String,
                    at stop: String) async throws -> TrainAtStop {
        let train = try await client.fetchTrain(id: identifier)
        guard let station = train.stations.first(where: { $0.code == stop }) else {
            throw AmtrakClientError.noStationFound(id: stop)
        }
        return TrainAtStop(train: Train(train: train),
                           stop: Stop(station: station))
    }
}
