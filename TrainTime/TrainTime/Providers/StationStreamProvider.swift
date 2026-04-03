import GRDB

protocol StationStreamProvider: Sendable {
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<Station?>
}

extension DatabasePool: StationStreamProvider {
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<Station?> {
        ValueObservation
            .tracking { db in
                try Station
                    .filter(Station.Columns.code == code)
                    .fetchOne(db)
            }
            .values(in: self)
    }
}
