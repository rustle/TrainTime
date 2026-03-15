import GRDB
import os

protocol FetchTrainProvider: Sendable {
    func fetchTrain(id: String) async throws -> TTTrain
}

extension TTClient: FetchTrainProvider {}

struct FetchTrainsProvider: Sendable {
    let fetchTrainProvider: FetchTrainProvider
    init(fetchTrainProvider: FetchTrainProvider) {
        self.fetchTrainProvider = fetchTrainProvider
    }
    func fetchTrains(batchSize: Int,
                     identifiers: [String]) async throws -> [TTTrain] {
        var trains = [TTTrain]()
        trains.reserveCapacity(identifiers.count)
        try await withThrowingTaskGroup(of: TTTrain?.self) { group in
            var index = 0
            while index < identifiers.count && index < batchSize {
                let id = identifiers[index]
                group.addTask {
                    do {
                        return try await withRetry(attempts: 3,
                                                   initialBackoff: .milliseconds(500)) { _ in
                            try await fetchTrainProvider.fetchTrain(id: id)
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
                                try await fetchTrainProvider.fetchTrain(id: id)
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
    func writeTrains(_: [TTTrain]) async throws -> Void
}

extension DatabasePool: WriteTrainsProvider {
    func writeTrains(_ trains: [TTTrain]) async throws {
        try await write { db in
            try trains.forEach { train in
                try train.upsert(db)
                try StopRecord
                    .filter(StopRecord.Columns.trainID == train.trainID)
                    .deleteAll(db)
                try train.stops.forEach { stationCode, stop in
                    try StopRecord(trainID: train.trainID, stationCode: stationCode, stop: stop).insert(db)
                }
            }
        }
    }
}

protocol TrainsStreamProvider: Sendable {
    func trains(identifiers: [String],
                stationCode: String?) async throws -> any AsyncThrowingSendableSequence<[TTTrain]>
}

extension DatabasePool: TrainsStreamProvider {
    func trains(identifiers: [String],
                stationCode: String?) async throws -> any AsyncThrowingSendableSequence<[TTTrain]> {
        ValueObservation
            .tracking { db in
                let trains: [TTTrain]
                if let stationCode {
                    let stopAlias = TableAlias()
                    let filteredStops = TTTrain.stopRecords
                        .aliased(stopAlias)
                        .filter(StopRecord.Columns.stationCode == stationCode)
                    trains = try TTTrain
                        .filter(ids: identifiers)
                        .joining(optional: filteredStops)
                        .order(stopAlias[StopRecord.Columns.schArr])
                        .fetchAll(db)
                } else {
                    trains = try TTTrain
                        .filter(ids: identifiers)
                        .fetchAll(db)
                }
                var stopFilter = identifiers.contains(StopRecord.Columns.trainID)
                if let stationCode {
                    stopFilter = stopFilter && StopRecord.Columns.stationCode == stationCode
                }
                let stopRecords = try StopRecord
                    .filter(stopFilter)
                    .fetchAll(db)
                let stopsByTrainID = Dictionary(grouping: stopRecords, by: \.trainID)
                return trains.map { train in
                    var t = train
                    t.stops = Dictionary(
                        uniqueKeysWithValues: (stopsByTrainID[train.trainID] ?? [])
                            .map { ($0.stationCode, $0.stop) }
                    )
                    return t
                }
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
              identifiers: [String]) async throws {
        let trains = try await fetchTrainsProvider
            .fetchTrains(batchSize: batchSize,
                         identifiers: identifiers)
        try await writeTrainsProvider.writeTrains(trains)
    }
    func trains(identifiers: [String],
                stationCode: String? = nil) async throws -> any AsyncThrowingSendableSequence<[TTTrain]> {
        try await trainsStreamProvider.trains(identifiers: identifiers,
                                              stationCode: stationCode)
    }
}
