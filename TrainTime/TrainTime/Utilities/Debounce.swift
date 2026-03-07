import Synchronization

final class Debounce<T: Sendable>: Sendable {
    // This is gross, but it gets the compiler to believe the handler
    // passed to init and the handler property have the same type
    private struct Handler: Sendable {
        let closure: @Sendable (T, isolated (any Actor)?) async -> Void
    }
    private let _handler: Handler
    private var handler: @Sendable (T, isolated (any Actor)?) async -> Void {
        _handler.closure
    }
    private let duration: ContinuousClock.Duration
    private let tolerance: ContinuousClock.Duration?
    private let mutex = Mutex<(task: Task<Void, Never>?, lastValue: T?)>((nil, nil))
    private let isolation: (any Actor)?

    init(
        duration: ContinuousClock.Duration,
        tolerance: ContinuousClock.Duration? = nil,
        @_inheritActorContext _ handler: @escaping @Sendable (T, isolated (any Actor)?) async -> Void,
        _ isolation: (any Actor)? = #isolation
    ) {
        self.duration = duration
        self.tolerance = tolerance
        self.isolation = isolation
        self._handler = .init(closure: handler)
    }

    deinit {
        mutex.withLock { state in
            state.task?.cancel()
        }
    }

    @discardableResult
    func emit(value: T) -> Task<Void, Never> {
        mutex.withLock { state in
            state.task?.cancel()
            state.lastValue = value
            let task = Task { [weak self, duration, tolerance, isolation] in
                guard self != nil else {
                    return
                }
                try? await Task.sleep(for: duration,
                                      tolerance: tolerance)
                guard let self, !Task.isCancelled else {
                    return
                }
                await self.handler(value, isolation)
            }
            state.task = task
            return task
        }
    }

    @discardableResult
    func flush() -> Task<Void, Never>? {
        mutex.withLock { state in
            state.task?.cancel()
            if let value = state.lastValue {
                let task = Task { [weak self, isolation] in
                    guard let self else {
                        return
                    }
                    await self.handler(value, isolation)
                }
                state.task = task
                return task
            } else {
                state.task = nil
                return nil
            }
        }
    }
}


extension Debounce where T == Void {
    convenience init(
        duration: ContinuousClock.Duration,
        tolerance: ContinuousClock.Duration? = nil,
        @_inheritActorContext handler: @Sendable @escaping (isolated (any Actor)?) async -> Void,
        _ isolation: (any Actor)? = #isolation
    ) {
        self.init(duration: duration,
                  tolerance: tolerance) { value, isolated in
            await handler(isolated)
        }
    }

    @discardableResult
    func emit() -> Task<Void, Never> {
        self.emit(value: ())
    }
}
