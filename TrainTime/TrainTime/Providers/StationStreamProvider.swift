import GRDB

protocol StationStreamProvider: Sendable {
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<TTStation?>
}

extension DatabasePool: StationStreamProvider {
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<TTStation?> {
        ValueObservation
            .tracking { db in
                try TTStation
                    .filter(TTStation.Columns.code == code)
                    .fetchOne(db)
            }
            .values(in: self)
    }
}
