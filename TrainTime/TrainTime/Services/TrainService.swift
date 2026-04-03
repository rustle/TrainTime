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
    func fetchTrains(batchSize: Int,
                     identifiers: [String],
                     at stop: String) async throws -> [TrainAtStop] {
        var trains = [TrainAtStop]()
        trains.reserveCapacity(identifiers.count)
        try await withThrowingTaskGroup(of: TrainAtStop?.self) { group in
            var index = 0
            while index < identifiers.count && index < batchSize {
                let id = identifiers[index]
                group.addTask {
                    do {
                        return try await withRetry(attempts: 3,
                                                   initialBackoff: .milliseconds(500)) { _ in
                            try await fetchTrainProvider.fetchTrain(identifier: id,
                                                                    at: stop)
                        }
                    } catch {
                        Logger.service.error("Failed to fetch train \(id) after retries: \(error)")
                        return nil
                    }
                }
                index += 1
            }
            while let train = try await group.next() {
                if let train { trains.append(train) }
                if index < identifiers.count {
                    let id = identifiers[index]
                    group.addTask {
                        do {
                            return try await withRetry(attempts: 3,
                                                       initialBackoff: .milliseconds(500)) { _ in
                                try await fetchTrainProvider.fetchTrain(identifier: id,
                                                                        at: stop)
                            }
                        } catch {
                            Logger.service.error("Failed to fetch train \(id) after retries: \(error)")
                            return nil
                        }
                    }
                    index += 1
                }
            }
        }
        return trains
    }
}

protocol WriteTrainsProvider: Sendable {
    func writeTrainAtStop(_: [TrainAtStop]) async throws -> Void
}

extension DatabasePool: WriteTrainsProvider {
    func writeTrainAtStop(_ trains: [TrainAtStop]) async throws {
        try await write { db in
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
        let trains = try await fetchTrainsProvider
            .fetchTrains(batchSize: batchSize,
                         identifiers: identifiers,
                         at: stop)
        try await writeTrainsProvider.writeTrainAtStop(trains)
    }
    func trains(identifiers: [String],
                at stop: String) async throws -> any AsyncThrowingSendableSequence<[TrainAtStop]> {
        try await trainsStreamProvider.trains(identifiers: identifiers,
                                              at: stop)
    }
}
