import Amtrak
@testable import TrainTime

// MARK: - TestUserDataProvider

final class TestUserDataProvider: WriteUserDataForStationProvider, Sendable {
    func writeUserDataForStation(code: String,
                                 isFavorite: Bool?) async throws {}
}

// MARK: - TestAPIService

private let allStations: TTStationResponse = [
    "UCA": .ucaFixture,
    "ROC": .rocFixture,
    "SYR": .syrFixture,
    "NYP": .nypFixture,
]

private let allTrains: [String: TTTrain] = [
    "48-1":  .train48Fixture,
    "63-2":  .train63Fixture,
    "64-2":  .train64Fixture,
    "280-2": .train280Fixture,
    "281-2": .train281Fixture,
    "284-2": .train284Fixture,
]

final class TestAPIService: Sendable, FetchAllStationsProvider, FetchStationProvider, FetchTrainProvider {
    func fetchAllStations() async throws -> TrainTime.TTStationResponse {
        allStations
    }

    func fetchStation(id: String) async throws -> TrainTime.TTStation {
        guard let station = allStations[id] else { throw ClientError.noStationFound(id: id) }
        return station
    }

    func fetchTrain(id: String) async throws -> TrainTime.TTTrain {
        guard let train = allTrains[id] else { throw ClientError.noTrainFound(id: id) }
        return train
    }
}
