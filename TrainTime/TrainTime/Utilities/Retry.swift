func withRetry<T: Sendable>(
    attempts: Int,
    initialBackoff: Duration,
    maximumBackoff: Duration = .seconds(30),
    @_inheritActorContext _ operation: @Sendable (isolated (any Actor)?) async throws -> T,
    _ isolation: (any Actor)? = #isolation
) async throws -> T {
    var remaining = attempts
    var delay = initialBackoff

    while true {
        do {
            return try await operation(isolation)
        } catch where error is CancellationError {
            throw error
        } catch {
            guard remaining > 1 else {
                throw error
            }
            remaining -= 1

            let jitter = Double.random(in: 0.8...1.2)
            let sleepDuration = min(delay * jitter, maximumBackoff)

            try await Task.sleep(for: sleepDuration)

            delay = min(delay * 2, maximumBackoff)
        }
    }
}
