import Amtrak
import Foundation
import Synchronization
import os
import Observation
import SwiftConcurrencySerialQueue

struct TrainRow: Identifiable, Sendable, Comparable {
    static func < (lhs: TrainRow,
                   rhs: TrainRow) -> Bool {
        lhs.stop.schArr < rhs.stop.schArr
    }
    let id: String
    let train: TTTrain
    let stop: Stop
    init(train: TTTrain, stop: Stop) {
        self.train = train
        self.stop = stop
        self.id = train.trainID
    }
}

enum StationViewStateError: Error {
    case missingStationData
}

@MainActor
@Observable
class StationViewState {
    private(set) var station: TTStation
    var title: String {
        station.name ?? station.code
    }
    private(set) var trains: [TrainRow] = []
    init(station: TTStation) {
        self.station = station
    }
    private let loadQueue = SerialQueueThrowing()
    private var loadDebounce: Debounce<Bool>?
    func load(with client: TTClient, refreshStation: Bool = false) async throws {
        Logger.viewState.debug("StationViewState: load(refreshStation: \(refreshStation))")
        if loadDebounce == nil {
            loadDebounce = Debounce(duration: .milliseconds(200),
                                    tolerance: .milliseconds(100)) { [weak self] refreshStation, _ in
                await self?._load(with: client,
                                  refreshStation: refreshStation)
            }
        }
        // Might be nice to have refreshStation latch during debounce
        await loadDebounce?.emit(value: refreshStation).value
    }
    private func _load(with client: TTClient,
                       refreshStation: Bool = false) async {
        let stationCode = station.code
        do {
            if (refreshStation) {
                Logger.viewState.debug("StationViewState: Refresh station")
                station = try await loadQueue.enqueue { _ in
                    try await client.fetchStation(id: stationCode)
                }
            }
            Logger.viewState.debug("StationViewState: Refresh trains")
            let trainIdentifiers = station.trainIdentifiers
            trains = try await loadQueue
                .enqueue { _ in
                    try await self._batch(with: client,
                                          size: 3,
                                          stationCode: stationCode,
                                          trainIdentifiers: trainIdentifiers)
                }
        } catch {
            Logger.viewState.error("StationViewState: load() error \(error)")
        }
    }
    private func _batch(with client: TTClient,
                        size: Int,
                        stationCode: String,
                        trainIdentifiers: [String]) async throws -> [TrainRow] {
        var trains = [TrainRow]()
        trains.reserveCapacity(trainIdentifiers.count)
        try await withThrowingTaskGroup(of: TrainRow?.self) { group in
            func fetchTrainRow(_ id: String) async -> TrainRow? {
                let train: TTTrain
                do {
                    train = try await client.fetchTrain(id: id)
                } catch {
                    Logger.viewState.error("Unexpected nil train - Station Code: \(stationCode), Train ID: \(id)")
                    return nil
                }
                guard let stop = train.stops[stationCode] else {
                    return nil
                }
                return TrainRow(train: train,
                                stop: stop)
            }
            let ids = trainIdentifiers
            var index = 0
            while index < ids.count && index < size {
                let id = ids[index]
                group.addTask {
                    await fetchTrainRow(id)
                }
                index += 1
            }
            while let row = try await group.next() {
                row.flatMap { trains.sortedInsert($0) }
                if index < ids.count {
                    let id = ids[index]
                    group.addTask {
                        await fetchTrainRow(id)
                    }
                    index += 1
                }
            }
        }
        Logger.viewState.debug("\(trains)")
        return trains
    }
}
