import Amtrak
@testable import TrainTime

// MARK: - TestUserDataProvider

final class TestUserDataProvider: WriteUserDataForStationProvider, Sendable {
    func writeUserDataForStation(code: String,
                                 isFavorite: Bool?) async throws {}
}

// MARK: - TestAPIService

private let allStations: [TrainTime.Station] = [
    .ucaFixture,
    .rocFixture,
    .syrFixture,
    .nypFixture,
]

private let allTrains: [TrainWithStops] = [
    TrainWithStops(train: .train48Fixture,
                   stops: .train48StopsFixture),
    TrainWithStops(train: .train63Fixture,
                   stops: .train63StopsFixture),
    TrainWithStops(train: .train64Fixture,
                   stops: .train64StopsFixture),
    TrainWithStops(train: .train280Fixture,
                   stops: .train280StopsFixture),
    TrainWithStops(train: .train281Fixture,
                   stops: .train281StopsFixture),
    TrainWithStops(train: .train284Fixture,
                   stops: .train284StopsFixture),
]

final class TestAPIService: Sendable, FetchAllStationsProvider, FetchStationProvider, FetchTrainProvider {
    func fetchStations() async throws -> [TrainTime.Station] {
        allStations
    }

    func fetchStation(code: String) async throws -> TrainTime.Station {
        guard let station = allStations.first(where: { $0.code == code }) else { throw AmtrakClientError.noStationFound(id: code) }
        return station
    }

    func fetchTrain(identifier: String,
                    at stop: String) async throws -> TrainAtStop {
        guard let trainWithStops = allTrains.first(where: { $0.train.trainID == identifier }) else { throw AmtrakClientError.noTrainFound(id: identifier) }
        guard let stop = trainWithStops.stops.first(where: { $0.code == stop }) else { throw AmtrakClientError.noTrainFound(id: identifier) }
        return TrainAtStop(train: trainWithStops.train,
                           stop: stop)
    }
}
