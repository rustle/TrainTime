import Amtrak
import Observation
import os
import Foundation
import SwiftConcurrencySerialQueue

@MainActor
@Observable
class StationListState {
    var selectedStation: StationRow?
    private(set) var allRows: [StationRow] = []
    private(set) var filteredRows: [StationRow]?
    var query: String = ""
    let component: StationListDependency
    init(component: StationListDependency) {
        self.component = component
        loadDebounce = Debounce(duration: .milliseconds(150),
                                tolerance: .milliseconds(100)) { [weak self] client, _ in
            await self?._load()
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
    private let loadQueue = SerialQueueThrowing()
    @ObservationIgnored private var loadDebounce: Debounce<Void>?
    func load() async throws {
        Logger.viewState.debug("StationListState: load()")
        await loadDebounce?.emit().value
    }
    private func _load() async {
        do {
            try await component.service.load()
            observeDatabaseIfNeeded()
        } catch {
            Logger.viewState.error("StationListState: load() error \(error)")
        }
    }
    func flush() {
        search.flush()
    }
    private var rowsTask: Task<Void, any Error>?
    private func observeDatabaseIfNeeded() {
        guard rowsTask == nil else {
            return
        }
        let stationsStream = self.component.service.stations
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
}
