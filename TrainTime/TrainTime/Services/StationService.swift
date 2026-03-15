import Amtrak
import GRDB

protocol FetchStationProvider: Sendable {
    func fetchStation(id: String) async throws -> TTStation
}

extension APIService: FetchStationProvider {}

protocol WriteStationProvider: Sendable {
    func writeStation(_: TTStation) async throws -> Void
}

extension DatabasePool: WriteStationProvider {
    func writeStation(_ station: TTStation) async throws {
        try await write { db in
            try station.upsert(db)
        }
    }
}

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

struct StationService: Sendable {
    let fetchStationProvider: FetchStationProvider
    let writeStationProvider: WriteStationProvider
    let stationStreamProvider: StationStreamProvider
    init(fetchStationProvider: FetchStationProvider,
         writeStationProvider: WriteStationProvider,
         stationStreamProvider: StationStreamProvider) {
        self.fetchStationProvider = fetchStationProvider
        self.writeStationProvider = writeStationProvider
        self.stationStreamProvider = stationStreamProvider
    }
    func load(id: String) async throws {
        let station = try await fetchStationProvider.fetchStation(id: id)
        try await writeStationProvider.writeStation(station)
    }
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<TTStation?> {
        try await stationStreamProvider.station(code: code)
    }
}
