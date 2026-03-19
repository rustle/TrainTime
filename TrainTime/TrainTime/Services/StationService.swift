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
