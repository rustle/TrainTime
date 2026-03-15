import Testing
@testable import TrainTime

@MainActor
final class Counter {
    var value: Int = 0
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

struct RetryTests {
    @Test func succeedsOnFirstAttempt() async throws {
        let result = try await withRetry(attempts: 3,
                                         initialBackoff: .zero) { _ in
            42
        }
        #expect(result == 42)
    }

    @Test func succeedsOnSecondAttempt() async throws {
        let counter = Counter()
        let result = try await withRetry(attempts: 3,
                                         initialBackoff: .zero) { _ in
            let value = await counter.increment()
            if value < 2 {
                throw TestError()
            }
            return value
        }
        #expect(result == 2)
        #expect(await counter.value == 2)
    }

    @Test func succeedsOnThirdAttempt() async throws {
        let counter = Counter()
        let result = try await withRetry(attempts: 3,
                                         initialBackoff: .zero) { _ in
            let value = await counter.increment()
            if value < 3 {
                throw TestError()
            }
            return value
        }
        #expect(result == 3)
        #expect(await counter.value == 3)
    }

    @Test func zeroAttemptsRunsOperationOnce() async throws {
        let counter = Counter()
        await #expect(throws: TestError.self) {
            try await withRetry(attempts: 0,
                                initialBackoff: .zero) { _ in
                await counter.increment()
                throw TestError()
            }
        }
        #expect(await counter.value == 1)
    }

    @Test func negativeAttemptsRunsOperationOnce() async throws {
        let counter = Counter()
        await #expect(throws: TestError.self) {
            try await withRetry(attempts: -1,
                                initialBackoff: .zero) { _ in
                await counter.increment()
                throw TestError()
            }
        }
        #expect(await counter.value == 1)
    }

    @Test func exhaustedRetriesThrowsLastError() async throws {
        let counter = Counter()
        await #expect(throws: TestError.self) {
            try await withRetry(attempts: 3,
                                initialBackoff: .zero) { _ in
                await counter.increment()
                throw TestError()
            }
        }
        #expect(await counter.value == 3)
    }
}

private struct TestError: Error, Equatable {}
