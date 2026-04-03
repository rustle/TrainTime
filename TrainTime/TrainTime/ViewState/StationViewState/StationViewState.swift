import Amtrak
import Foundation
import os
import Observation
import SwiftConcurrencySerialQueue

@MainActor
@Observable
final class StationViewState {
    private(set) var station: Station
    var title: String {
        station.name ?? station.code
    }
    private(set) var trains: [TrainRow] = []
    let component: StationComponent
    init(station: Station,
         component: StationComponent) {
        self.station = station
        self.component = component
        loadDebounce = Debounce(duration: .milliseconds(150),
                                tolerance: .milliseconds(100)) { [weak self] refreshStation, _ in
            await self?._load(refreshStation: refreshStation)
        }
    }
    // It's weird for this too stay here and not move to a service
    // but it's coordinating two services right now.
    // Might make one service that packs up the two to clean this up.
    private let loadQueue = SerialQueueThrowing()
    private var loadDebounce: Debounce<Bool>?
    func load(refreshStation: Bool = false) async throws {
        Logger.viewState.debug("StationViewState: load(refreshStation: \(refreshStation))")
        // Might be nice to have refreshStation latch during debounce
        await loadDebounce?.emit(value: refreshStation).value
    }
    private func _load(refreshStation: Bool) async {
        let stationCode = station.code
        do {
            try await observeDatabaseIfNeeded()
            if (refreshStation) {
                Logger.viewState.debug("StationViewState: Refresh station")
                try await loadQueue.enqueue { [stationService=self.component.stationService] _ in
                    try await stationService.load(stationCode: stationCode)
                }
            }
            Logger.viewState.debug("StationViewState: Refresh trains")
            let trainIdentifiers = station.trainIdentifiers
            try await loadQueue
                .enqueue { [trainService=self.component.trainService] _ in
                    try await trainService
                        .load(batchSize: 3,
                              identifiers: trainIdentifiers,
                              at: stationCode)
                }
        } catch {
            Logger.viewState.error("StationViewState: load() error \(error)")
        }
    }
    private var stationTask: Task<Void, any Error>?
    private var trainsTask: Task<Void, any Error>?
    private func observeDatabaseIfNeeded() async throws {
        if stationTask == nil {
            let stationStream = try await self.component.stationService.station(code: station.code)
            stationTask = Task { @MainActor [weak self] in
                for try await station in stationStream {
                    guard let self else {
                        break
                    }
                    guard let station else {
                        break
                    }
                    self.station = station
                }
            }
        }
        if trainsTask == nil {
            let trainsStream = try await self.component.trainService
                .trains(identifiers: station.trainIdentifiers,
                        at: station.code)
            trainsTask = Task { @MainActor [weak self] in
                for try await trains in trainsStream {
                    guard let self else {
                        break
                    }
                    self.trains = trains.compactMap(TrainRow.init(trainAtStop:))
                }
            }
        }
    }
}
