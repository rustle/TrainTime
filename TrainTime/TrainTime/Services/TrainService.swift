import Amtrak
import GRDB
import os

protocol FetchTrainProvider: Sendable {
    func fetchTrain(identifier: String,
                    at stop: String) async throws -> TrainAtStop
}

extension APIService: FetchTrainProvider {}

/// The result of fetching a batch of trains for one station.
struct FetchedTrainsAtStop: Sendable {
    /// Trains that were fetched successfully.
    var trains: [TrainAtStop] = []
    /// Identifiers the API definitively reports as no longer stopping at the
    /// station. Transient failures are *not* listed here, so their persisted
    /// stops survive until the API says otherwise.
    var departedIdentifiers: Set<String> = []
}

struct FetchTrainsProvider: Sendable {
    let fetchTrainProvider: FetchTrainProvider
    init(fetchTrainProvider: FetchTrainProvider) {
        self.fetchTrainProvider = fetchTrainProvider
    }
    private enum FetchOutcome: Sendable {
        case fetched(TrainAtStop)
        /// The train exists but no longer calls at the requested station.
        case departed(String)
        case failed
    }
    private func fetchTrain(identifier: String,
                            at stop: String) async throws -> FetchOutcome {
        do {
            return try await withRetry(attempts: 3,
                                       initialBackoff: .milliseconds(500)) { _ in
                do {
                    return .fetched(try await fetchTrainProvider.fetchTrain(identifier: identifier,
                                                                            at: stop))
                } catch AmtrakClientError.noStationFound {
                    // Deterministic, not transient: returning short-circuits the retry.
                    return .departed(identifier)
                } catch AmtrakClientError.noTrainFound {
                    // The run itself is gone (finished, or the ID was recycled),
                    // so its stop here is stale too. Also deterministic.
                    return .departed(identifier)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.service.error("Failed to fetch train \(identifier) after retries: \(error)")
            return .failed
        }
    }
    func fetchTrains(batchSize: Int,
                     identifiers: [String],
                     at stop: String) async throws -> FetchedTrainsAtStop {
        var result = FetchedTrainsAtStop()
        result.trains.reserveCapacity(identifiers.count)
        try await withThrowingTaskGroup(of: FetchOutcome.self) { group in
            var index = 0
            func addNextTask() {
                guard index < identifiers.count else { return }
                let id = identifiers[index]
                index += 1
                group.addTask {
                    try await fetchTrain(identifier: id,
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
            // Drop stops this station no longer serves, so a train that stops
            // being listed here can't linger in the joined observation.
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
        guard !identifiers.isEmpty else {
            // Nothing to fetch, and nothing to keep either: writing an empty
            // `keeping` set would delete every stop cached for this station.
            // An empty list mostly means the station's detail hasn't been
            // fetched yet, not that it serves no trains.
            return
        }
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
