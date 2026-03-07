import Observation
import os
import SwiftUI

@MainActor
@Observable
final class Search<T> where T: Sendable, T: Equatable {
    private enum UpdatedQuery: Sendable, Equatable {
        case enqueued(Int, String)
        case working(Int, String)
        case done(Int)
    }
    @ObservationIgnored private var value: T
    private(set) var filteredValue: T? = nil
    @ObservationIgnored private var query: String = ""
    @ObservationIgnored private var updateQueryDebounce: Debounce<String>?
    @ObservationIgnored private var updatedQuery: UpdatedQuery = .done(generation: 0)
    @ObservationIgnored private var filterTask: Task<T?, Never>? = nil
    @ObservationIgnored private var filter: @Sendable (String, T) async -> T
    init(initialValue: T, filter: @Sendable @escaping (String, T) async -> T) {
        self.value = initialValue
        self.filter = filter
        updateQueryDebounce = Debounce(duration: .milliseconds(200), tolerance: .milliseconds(50)) { [weak self] value, _ in
            guard let self else {
                return
            }
            await self.updateQueryIfNeeded(value: value)
        }
    }
    func update(value: T) {
        if self.value == value {
            return
        }
        self.value = value
        Task {
            // Rerun filter using any waiting updatedQuery
            // or putting the settled query value back into
            // updatedQuery
            switch updatedQuery {
            case .enqueued(let generation, let query):
                fallthrough
            case .working(let generation, let query):
                updatedQuery = .enqueued(generation + 1,
                                         query)
            case .done(let generation):
                updatedQuery = .enqueued(generation + 1,
                                         query)
            }
            await applyFilter()
        }
    }
    func update(query: String) {
        updateQueryDebounce?.emit(value: query)
    }
    func flush() {
        updateQueryDebounce?.flush()
    }
    private func updateQueryIfNeeded(value: String) async {
        // If we have an updatedQuery, make sure value is a change from it
        // If we don't, make sure value is a change from the settled query value
        switch updatedQuery {
        case .enqueued(let generation, let query):
            fallthrough
        case .working(let generation, let query):
            guard value != query else {
                return
            }
            self.updatedQuery = .enqueued(generation + 1,
                                          value)
        case .done(let generation):
            guard value != query else {
                return
            }
            self.updatedQuery = .enqueued(generation + 1,
                                          value)
        }
        await self.applyFilter()
    }
    private func applyFilter() async {
        guard case let .enqueued(generationEnqueued,
                                 updatedQuery) = updatedQuery else {
            return
        }
        Logger.utilities.debug("Search: filter(\(updatedQuery))")
        filterTask?.cancel()
        self.updatedQuery = .working(generationEnqueued,
                                     updatedQuery)
        guard updatedQuery.count > 0 else {
            query = ""
            filteredValue = nil
            return
        }
        let task: Task<T?, Never> = Task.detached(priority: TaskPriority.userInitiated) { [value, filter] in
            guard !Task.isCancelled else {
                return nil
            }
            return await filter(updatedQuery, value)
        }
        filterTask = task
        if let result = await task.value,
           !task.isCancelled,
           case let .working(generationWorking, _) = self.updatedQuery,
           generationWorking == generationEnqueued {
            query = updatedQuery
            filteredValue = result
            self.updatedQuery = .done(generationWorking)
        }
        if filterTask == task {
            filterTask = nil
        }
    }
}
