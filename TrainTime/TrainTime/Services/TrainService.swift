import GRDB
import os

struct TrainService {
    let client: TTClient
    let databaseConnection: DatabasePool
    init(client: TTClient,
         databaseConnection: DatabasePool) {
        self.client = client
        self.databaseConnection = databaseConnection
    }
    func load(id: String) async throws {
        let train = try await client
            .fetchTrain(id: id)
        try await databaseConnection.write { db in
            try train.upsert(db)
        }
    }
    func load(identifiers: [String]) async throws {
        let trains = try await batch(size: 3,
                                     identifiers: identifiers)
        try await databaseConnection.write { db in
            try trains.forEach { try $0.upsert(db) }
        }
    }
    // TODO: Retry with backoff
    private func batch(size: Int,
                       identifiers: [String]) async throws -> [TTTrain] {
        var trains = [TTTrain]()
        trains.reserveCapacity(identifiers.count)
        try await withThrowingTaskGroup(of: TTTrain.self) { group in
            var index = 0
            while index < identifiers.count && index < size {
                let id = identifiers[index]
                group.addTask {
                    try await client
                        .fetchTrain(id: id)
                }
                index += 1
            }
            while let train = try await group.next() {
                trains.append(train)
                if index < identifiers.count {
                    let id = identifiers[index]
                    group.addTask {
                        try await client
                            .fetchTrain(id: id)
                    }
                    index += 1
                }
            }
        }
        return trains
    }
}
