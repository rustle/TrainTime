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
    let component: StationComponent
    init(station: TTStation,
         component: StationComponent) {
        self.station = station
        self.component = component
        loadDebounce = Debounce(duration: .milliseconds(150),
                                tolerance: .milliseconds(100)) { [weak self] refreshStation, _ in
            await self?._load(refreshStation: refreshStation)
        }
    }
    private let loadQueue = SerialQueueThrowing()
    private var loadDebounce: Debounce<Bool>?
    func load(refreshStation: Bool = false) async throws {
        Logger.viewState.debug("StationViewState: load(refreshStation: \(refreshStation))")
        // Might be nice to have refreshStation latch during debounce
        await loadDebounce?.emit(value: refreshStation).value
    }
    private func _load(refreshStation: Bool = false) async {
        let stationCode = station.code
        do {
            if (refreshStation) {
                Logger.viewState.debug("StationViewState: Refresh station")
                let client = component.client
                station = try await loadQueue.enqueue { _ in
                    try await client.fetchStation(id: stationCode)
                }
            }
            Logger.viewState.debug("StationViewState: Refresh trains")
            let trainIdentifiers = station.trainIdentifiers
            trains = try await loadQueue
                .enqueue { _ in
                    try await self._batch(size: 3,
                                          stationCode: stationCode,
                                          trainIdentifiers: trainIdentifiers)
                }
        } catch {
            Logger.viewState.error("StationViewState: load() error \(error)")
        }
    }
    private func _batch(size: Int,
                        stationCode: String,
                        trainIdentifiers: [String]) async throws -> [TrainRow] {
        let client = component.client
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
