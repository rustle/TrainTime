import Amtrak
import GRDB
import os

protocol FetchTrainProvider: Sendable {
    func fetchTrain(identifier: String,
                    at stop: String) async throws -> TrainAtStop
}

extension APIService: FetchTrainProvider {}

struct FetchTrainsProvider: Sendable {
    let fetchTrainProvider: FetchTrainProvider
    init(fetchTrainProvider: FetchTrainProvider) {
        self.fetchTrainProvider = fetchTrainProvider
    }
    /// The result of fetching a batch of trains for one station.
    struct TrainsAtStop: Sendable {
        /// Trains that were fetched successfully.
        var trains: [TrainAtStop] = []
        /// Identifiers the API definitively reports as no longer stopping at the
        /// station. Transient failures are *not* listed here, so their persisted
        /// stops survive until the API says otherwise.
        var departedIdentifiers: Set<String> = []
    }
    private enum Status: Sendable {
        case fetched(TrainAtStop)
        case departed(String)
        case failed
    }
    private func fetchTrain(identifier: String,
                            at stop: String) async -> Status {
        do {
            return try await withRetry(attempts: 3,
                                       initialBackoff: .milliseconds(500)) { _ in
                do {
                    return .fetched(try await fetchTrainProvider.fetchTrain(identifier: identifier,
                                                                            at: stop))
                } catch AmtrakClientError.noStationFound {
                    return .departed(identifier)
                }
            }
        } catch {
            Logger.service.error("Failed to fetch train \(identifier) after retries: \(error)")
            return .failed
        }
    }
    func fetchTrains(batchSize: Int,
                     identifiers: [String],
                     at stop: String) async throws -> TrainsAtStop {
        var result = TrainsAtStop()
        result.trains.reserveCapacity(identifiers.count)
        try await withThrowingTaskGroup(of: Status.self) { group in
            var index = 0
            func addNextTask() {
                guard index < identifiers.count else { return }
                let id = identifiers[index]
                index += 1
                group.addTask {
                    await fetchTrain(identifier: id,
                                     at: stop)
                }
            }
            while index < min(batchSize, identifiers.count) {
                addNextTask()
            }
            while let outcome = try await group.next() {
                switch outcome {
                case .fetched(let train):
                    result.trains.append(train)
                case .departed(let id):
                    result.departedIdentifiers.insert(id)
                case .failed:
                    break
                }
                addNextTask()
            }
        }
        return result
    }
}

protocol WriteTrainsProvider: Sendable {
    func writeTrainAtStop(_: [TrainAtStop],
                          at stop: String,
                          keeping identifiers: Set<String>) async throws -> Void
}

extension DatabasePool: WriteTrainsProvider {
    func writeTrainAtStop(_ trains: [TrainAtStop],
                          at stop: String,
                          keeping identifiers: Set<String>) async throws {
        try await write { db in
            // Drop stops this station no longer serves.
            try StopRecord
                .filter(StopRecord.Columns.stationCode == stop)
                .filter(!identifiers.contains(StopRecord.Columns.trainID))
                .deleteAll(db)
            try trains.forEach { train in
                try train.train.upsert(db)
                try StopRecord(trainID: train.train.trainID,
                               stationCode: train.stop.code,
                               stop: train.stop)
                    .upsert(db)
            }
        }
    }
}

protocol TrainsStreamProvider: Sendable {
    func trains(identifiers: [String],
                at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]>
}

extension DatabasePool: TrainsStreamProvider {
    func trains(identifiers: [String],
                at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]> {
        ValueObservation
            .tracking { db in
                let stopAlias = TableAlias()
                let request = Train
                    .filter(ids: identifiers)
                    .including(required: Train.stopRecords
                        .aliased(stopAlias)
                        .filter(StopRecord.Columns.stationCode == stop)
                        .order(stopAlias[StopRecord.Columns.schArr])
                        .forKey("stop")
                    )
                return try TrainAtStop
                    .fetchAll(db,
                              request)
            }
            .values(in: self)
    }
}

struct TrainService: Sendable {
    let fetchTrainsProvider: FetchTrainsProvider
    let writeTrainsProvider: WriteTrainsProvider
    let trainsStreamProvider: TrainsStreamProvider
    init(fetchTrainProvider: FetchTrainProvider,
         writeTrainsProvider: WriteTrainsProvider,
         trainsStreamProvider: TrainsStreamProvider) {
        self.fetchTrainsProvider = .init(fetchTrainProvider: fetchTrainProvider)
        self.writeTrainsProvider = writeTrainsProvider
        self.trainsStreamProvider = trainsStreamProvider
    }
    init(fetchTrainsProvider: FetchTrainsProvider,
         writeTrainsProvider: WriteTrainsProvider,
         trainsStreamProvider: TrainsStreamProvider) {
        self.fetchTrainsProvider = fetchTrainsProvider
        self.writeTrainsProvider = writeTrainsProvider
        self.trainsStreamProvider = trainsStreamProvider
    }
    func load(batchSize: Int = 3,
              identifiers: [String],
              at stop: String) async throws {
        let result = try await fetchTrainsProvider
            .fetchTrains(batchSize: batchSize,
                         identifiers: identifiers,
                         at: stop)
        let liveIdentifiers = Set(identifiers)
            .subtracting(result.departedIdentifiers)
        try await writeTrainsProvider.writeTrainAtStop(result.trains,
                                                       at: stop,
                                                       keeping: liveIdentifiers)
    }
    func trains(identifiers: [String],
                at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]> {
        try await trainsStreamProvider.trains(identifiers: identifiers,
                                              at: stop)
    }
}
