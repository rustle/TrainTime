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
    /// Favorites in the user's order; the rows a person can move.
    private(set) var favoriteRows: [StationRow] = []
    /// Everything that isn't a favorite, by name.
    private(set) var otherRows: [StationRow] = []
    private(set) var filteredRows: [StationRow]?
    var query: String = ""
    let component: StationListDependency
    init(component: StationListDependency) {
        self.component = component
        loadDebounce = Debounce(duration: .milliseconds(150),
                                tolerance: .milliseconds(100)) { [weak self] _, _ in
            await self?._load()
        }
        writeDebounce = Debounce(duration: .milliseconds(150),
                                 tolerance: .milliseconds(100)) { [weak self] _, _ in
            await self?.writePendingChanges()
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
            favoriteRows = allRows.filter { $0.station.isFavorite == true }
            otherRows = allRows.filter { $0.station.isFavorite != true }
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
    // MARK: - Favorites
    private var favoritePositions: [FavoritePosition] {
        favoriteRows.map {
            FavoritePosition(code: $0.station.code,
                             sortOrder: $0.station.favoriteSortOrder)
        }
    }
    /// Favorites or unfavorites a station. A new favorite goes to the end
    /// of the favorites, the way Weather, Stocks and Clock add to their lists.
    func toggleFavorite(code: String) {
        if let index = favoriteRows.firstIndex(where: { $0.station.code == code }) {
            var favorites = favoriteRows
            let row = favorites.remove(at: index)
            var others = otherRows
            others.sortedInsert(row.updating(isFavorite: nil,
                                             sortOrder: nil))
            apply(favorites: favorites,
                  others: others,
                  changes: [FavoritesOrdering.changeRemoving(code)])
        } else if let index = otherRows.firstIndex(where: { $0.station.code == code }) {
            var others = otherRows
            let row = others.remove(at: index)
            let changes = FavoritesOrdering.changes(adding: code,
                                                    to: favoritePositions)
            apply(favorites: favoriteRows + [row.updating(isFavorite: true,
                                                          sortOrder: nil)],
                  others: others,
                  changes: changes)
        }
    }
    /// Moves favorites the way `List.onMove` reports it.
    func moveFavorites(fromOffsets source: IndexSet,
                       toOffset destination: Int) {
        guard source.allSatisfy(favoriteRows.indices.contains),
              (0...favoriteRows.count).contains(destination) else {
            return
        }
        let moved = Set(source.map { favoriteRows[$0].station.code })
        reorder(favorites: favoriteRows.moving(fromOffsets: source,
                                               toOffset: destination),
                moved: moved)
    }
    /// Moves one favorite up (negative) or down (positive) by `delta` rows,
    /// stopping at the ends.
    func moveFavorite(code: String,
                      by delta: Int) {
        guard let index = favoriteRows.firstIndex(where: { $0.station.code == code }) else {
            return
        }
        let target = min(max(index + delta, 0), favoriteRows.count - 1)
        moveFavorite(code: code,
                     toIndex: target)
    }
    func moveFavoriteToTop(code: String) {
        moveFavorite(code: code,
                     toIndex: 0)
    }
    func moveFavoriteToBottom(code: String) {
        moveFavorite(code: code,
                     toIndex: favoriteRows.count - 1)
    }
    private func moveFavorite(code: String,
                              toIndex target: Int) {
        guard let index = favoriteRows.firstIndex(where: { $0.station.code == code }),
              favoriteRows.indices.contains(target),
              index != target else {
            return
        }
        var favorites = favoriteRows
        let row = favorites.remove(at: index)
        favorites.insert(row,
                         at: target)
        reorder(favorites: favorites,
                moved: [code])
    }
    private func reorder(favorites: [StationRow],
                         moved: Set<String>) {
        guard favorites != favoriteRows else {
            return
        }
        let changes = FavoritesOrdering.changes(
            for: favorites.map {
                FavoritePosition(code: $0.station.code,
                                 sortOrder: $0.station.favoriteSortOrder)
            },
            moved: moved
        )
        apply(favorites: favorites,
              others: otherRows,
              changes: changes)
    }
    /// Shows the change right away and persists it shortly after. Rows carry
    /// the positions being written so the database's echo compares equal and
    /// a second move before the write lands still sees current positions.
    private func apply(favorites: [StationRow],
                       others: [StationRow],
                       changes: [StationUserDataChange]) {
        let sortOrders = Dictionary(changes.map { ($0.code, $0.sortOrder) },
                                    uniquingKeysWith: { first, _ in first })
        favoriteRows = favorites.map { row in
            guard let sortOrder = sortOrders[row.station.code] else {
                return row
            }
            return row.updating(isFavorite: true,
                                sortOrder: sortOrder)
        }
        otherRows = others
        allRows = favoriteRows + otherRows
        enqueue(changes)
    }
    // MARK: - Writing
    /// Changes waiting for the debounce, latest per station, in the order
    /// they were made.
    @ObservationIgnored private var pendingChanges: [StationUserDataChange] = []
    @ObservationIgnored private var writeDebounce: Debounce<Void>?
    private func enqueue(_ changes: [StationUserDataChange]) {
        for change in changes {
            pendingChanges.removeAll { $0.code == change.code }
            pendingChanges.append(change)
        }
        writeDebounce?.emit()
    }
    private func writePendingChanges() async {
        let changes = pendingChanges
        pendingChanges.removeAll()
        guard !changes.isEmpty else {
            return
        }
        do {
            try await component.stationsService
                .writeUserData(changes)
        } catch {
            Logger.viewState.error("Failed to write user data for \(changes.map(\.code)) - \(error.localizedDescription)")
        }
    }
    // MARK: - Observation
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
}

private extension StationRow {
    func updating(isFavorite: Bool?,
                  sortOrder: Double?) -> StationRow {
        var station = self.station
        station.isFavorite = isFavorite
        station.favoriteSortOrder = sortOrder
        return StationRow(station: station)
    }
}
