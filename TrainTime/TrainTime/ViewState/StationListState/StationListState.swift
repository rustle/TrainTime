import Amtrak
import Observation
import os
import Foundation
import SwiftConcurrencySerialQueue

@MainActor
@Observable
final class StationListState {
    var selectedStation: StationRow?
    private(set) var allRows: [StationRow] = []
    private(set) var filteredRows: [StationRow]?
    var query: String = ""
    let component: StationListDependency
    init(component: StationListDependency) {
        self.component = component
        loadDebounce = Debounce(duration: .milliseconds(150),
                                tolerance: .milliseconds(100)) { [weak self] _, _ in
            await self?._load()
        }
        isFavoriteDebounce = Debounce(duration: .milliseconds(150),
                                      tolerance: .milliseconds(100)) { [weak self] value, _ in
            await self?._writeUserDataForStation(code: value.0,
                                                 isFavorite: value.1)
        }
        observe()
    }
    func update(filteredRows: [StationRow]?) {
        if self.filteredRows != filteredRows {
            self.filteredRows = filteredRows
        }
    }
    private func update(allRows: [StationRow]) {
        if self.allRows != allRows {
            Logger.viewState.debug("Update allRows")
            self.allRows = allRows
        }
    }
    private let search = Search<[StationRow]>(initialValue: []) { query, rows in
        rows.search(query: query)
    }
    @ObservationIgnored private var loadDebounce: Debounce<Void>?
    func load() async throws {
        Logger.viewState.debug("StationListState: load()")
        await loadDebounce?.emit().value
    }
    private func _load() async {
        do {
            try await observeDatabaseIfNeeded()
            try await component.stationsService.load()
        } catch {
            Logger.viewState.error("StationListState: load() error \(error)")
        }
    }
    func flush() {
        search.flush()
    }
    @ObservationIgnored private var isFavoriteDebounce: Debounce<(String, Bool?)>?
    func writeUserDataForStation(code: String,
                                 isFavorite: Bool?) {
        isFavoriteDebounce?.emit(value: (code, isFavorite))
    }
    private func _writeUserDataForStation(code: String,
                                          isFavorite: Bool?) async {
        do {
            try await component.stationsService
                .writeUserDataForStation(code: code,
                                         isFavorite: isFavorite)
        } catch {
            Logger.viewState.error("Failed to update isFavorite for \(code) - \(String(describing: isFavorite)) - \(error.localizedDescription)")
        }
    }
    @ObservationIgnored private var rowsTask: Task<Void, any Error>?
    private func observeDatabaseIfNeeded() async throws {
        guard rowsTask == nil else {
            return
        }
        let stationsStream = try await self.component.stationsService.stations()
        rowsTask = Task { @MainActor in
            for try await stations in stationsStream {
                update(allRows: stations.map(StationRow.init(station:)))
            }
        }
    }
    private func observe() {
        withObservationTracking {
            search.update(value: allRows)
            search.update(query: query)
            filteredRows = search.filteredValue
        } onChange: {
            Task { @MainActor in
                self.observe()
            }
        }
    }
    // MARK - Logs
    enum DebugToolBarItemState {
        case hide
        case show
        case preparing(Progress)
        case failed(Error)
    }
    private(set) var debugToolBarItemState: DebugToolBarItemState = .show
    private(set) var fileToShare: URL?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @MainActor
    func prepareDebugLogExport(timeWindow: LogExportService.TimeWindow) {
        exportTask?.cancel()

        let progress = Progress(totalUnitCount: 3)
        debugToolBarItemState = .preparing(progress)

        progressObservation = progress.observe(\.completedUnitCount) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                // Only update if we are still in the preparing state
                if case .preparing = self.debugToolBarItemState {
                    self.debugToolBarItemState = .preparing(progress)
                }
            }
        }

        exportTask = Task {
            do {
                try Task.checkCancellation()
                let url = try await generateFile(timeWindow: timeWindow,
                                                 progress: progress)
                try Task.checkCancellation()
                self.fileToShare = url
                self.debugToolBarItemState = .show
            } catch is CancellationError {
            } catch {
                self.debugToolBarItemState = .failed(error)
                try? await Task.sleep(for: .seconds(3))
                self.debugToolBarItemState = .show
            }
        }
    }
    private func generateFile(timeWindow: LogExportService.TimeWindow,
                              progress: Progress) async throws -> URL {
        progress.completedUnitCount = 0
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TrainTimeLogs.txt")
        progress.completedUnitCount = 1
        let logText = try await component.logExportService.export(timeWindow: timeWindow)
        try Task.checkCancellation()
        progress.completedUnitCount = 2
        try logText.write(to: url,
                          atomically: true,
                          encoding: .utf8)
        progress.completedUnitCount = 3
        return url
    }
}
