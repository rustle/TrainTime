import GRDB

struct StationService {
    let client: TTClient
    let databaseConnection: DatabasePool
    let trainService: TrainService
    init(client: TTClient,
         databaseConnection: DatabasePool,
         trainService: TrainService) {
        self.client = client
        self.databaseConnection = databaseConnection
        self.trainService = trainService
    }
    func load(id: String) async throws {
        let station = try await client
            .fetchStation(id: id)
        try await databaseConnection.write { db in
            try station.upsert(db)
        }
    }
}
