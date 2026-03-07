import Amtrak

final class TTClient: Sendable {
    private let client = Client()
    func fetchAllStations() async throws -> TTStationResponse {
        let response = try await client.fetchAllStations()
        return response.reduce(into: [:]) { accumulator, keyValue in
            let (stationId, stationMetadata) = keyValue
            accumulator[stationId] = .init(stationMetadata: stationMetadata)
        }
    }
    func fetchStation(id: String) async throws -> TTStation {
        let stationMetadata = try await client.fetchStation(id: id)
        return TTStation(stationMetadata: stationMetadata)
    }
    func fetchTrain(id: String) async throws -> TTTrain {
        return .init(train: try await client.fetchTrain(id: id))
    }
}
