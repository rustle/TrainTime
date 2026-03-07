import Amtrak
import Observation
import os
import Foundation
import SwiftConcurrencySerialQueue

@MainActor
@Observable
class StationListState {
    private(set) var allRows: [StationRow] = []
    private(set) var filteredRows: [StationRow]?
    var query: String = ""
    init() {
        loadDebounce = Debounce(duration: .milliseconds(200),
                                tolerance: .milliseconds(100)) { [weak self] client, _ in
            await self?._load(with: client)
        }
        observeState()
    }
    func update(filteredRows: [StationRow]?) {
        if self.filteredRows != filteredRows {
            self.filteredRows = filteredRows
        }
    }
    private func update(allRows: [StationRow]) {
        if self.allRows != allRows {
            self.allRows = allRows
        }
    }
    private let search = Search<[StationRow]>(initialValue: []) { query, rows in
        rows.search(query: query)
    }
    private let loadQueue = SerialQueueThrowing()
    @ObservationIgnored private var loadDebounce: Debounce<TTClient>?
    func load(with client: TTClient) async throws {
        Logger.viewState.debug("StationListState: load()")
        await loadDebounce?.emit(value: client).value
    }
    private func _load(with client: TTClient) async {
        do {
            update(allRows: try await loadQueue
                .enqueue { _ in
                    try await client
                        .fetchAllStations()
                }
                .sortedRows())
        } catch {
            Logger.viewState.error("StationListState: load() error \(error)")
        }
    }
    func flush() {
        search.flush()
    }
    private func observeState() {
        withObservationTracking {
            search.update(value: allRows)
            search.update(query: query)
            filteredRows = search.filteredValue
        } onChange: {
            Task(priority: .userInitiated) { @MainActor in
                self.observeState()
            }
        }
    }
}
