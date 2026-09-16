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
            // `observedTrainIdentifiers` is the observation's dedup key, not a
            // record of the newest list: its two writers (the refresh below and
            // the station observation) have no ordering between them, so it can
            // hold an older list than this call already knows about. Reading it
            // here would hand a stale list to `keeping:` and delete the stops of
            // every train the refresh had just added.
            let trainIdentifiers: [String]
            if (refreshStation) {
                Logger.viewState.debug("StationViewState: Refresh station")
                // Use the station the refresh returned: `self.station` is only
                // updated later, by the database observation.
                let refreshed = try await loadQueue
                    .enqueue { [stationService=self.component.stationService] _ in
                        try await stationService.load(stationCode: stationCode)
                    }
                trainIdentifiers = refreshed.trainIdentifiers
                try await observeTrains(identifiers: trainIdentifiers,
                                        at: stationCode)
            } else {
                trainIdentifiers = station.trainIdentifiers
            }
            Logger.viewState.debug("StationViewState: Refresh trains")
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
    private var observedTrainIdentifiers: [String]?
    private func observeDatabaseIfNeeded() async throws {
        if stationTask == nil {
            let stationStream = try await self.component.stationService.station(code: station.code)
            stationTask = Task { @MainActor [weak self] in
                for try await station in stationStream {
                    guard let self else {
                        break
                    }
                    guard let station else {
                        // A concurrent stations refresh can briefly delete this
                        // row; wait for it to come back rather than ending the
                        // observation for the view's lifetime.
                        continue
                    }
                    self.station = station
                    do {
                        // The station's train list changes over time; the trains
                        // observation has to be rebuilt to follow it.
                        try await self.observeTrains(identifiers: station.trainIdentifiers,
                                                     at: station.code)
                    } catch {
                        Logger.viewState.error("StationViewState: observeTrains() error \(error)")
                    }
                }
            }
        }
        try await observeTrains(identifiers: station.trainIdentifiers,
                                at: station.code)
    }
    private var trainsObservationGeneration = 0
    private func observeTrains(identifiers: [String],
                               at stationCode: String) async throws {
        guard observedTrainIdentifiers != identifiers else {
            return
        }
        // Claim these identifiers before suspending, so a concurrent call for
        // the same list is a no-op and a call for a *newer* list supersedes
        // this one rather than racing it.
        observedTrainIdentifiers = identifiers
        trainsObservationGeneration += 1
        let generation = trainsObservationGeneration
        let trainsStream: any AsyncThrowingSendableSequence<[TrainAtStop]>
        do {
            trainsStream = try await self.component.trainService
                .trains(identifiers: identifiers,
                        at: stationCode)
        } catch {
            // Release the claim, or the guard above would block every retry
            // and leave the view with no train observation at all.
            if generation == trainsObservationGeneration {
                observedTrainIdentifiers = nil
            }
            throw error
        }
        guard generation == trainsObservationGeneration else {
            // A newer list won while we were suspended; leave its task alone.
            return
        }
        trainsTask?.cancel()
        trainsTask = Task { @MainActor [weak self] in
            for try await trains in trainsStream {
                guard let self else {
                    break
                }
                guard generation == self.trainsObservationGeneration else {
                    // Cancellation is cooperative, so a value this task had
                    // already resumed with can land after a newer observation
                    // replaced it. Publishing it would leave the view showing
                    // the old list until the *new* observation happens to emit.
                    break
                }
                // Sorted here so views can count on chronological order.
                self.trains = trains
                    .map(TrainRow.init(trainAtStop:))
                    .sorted()
            }
        }
    }
}
