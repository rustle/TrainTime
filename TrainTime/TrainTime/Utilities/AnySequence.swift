typealias AsyncThrowingSendableSequence<V: Sendable> = AsyncSequence<V, any Error> & Sendable
