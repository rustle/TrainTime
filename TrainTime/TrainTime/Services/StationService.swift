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
    func load(stationCode: String) async throws {
        let station = try await fetchStationProvider.fetchStation(code: stationCode)
        try await writeStationProvider.writeStation(station)
    }
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<Station?> {
        try await stationStreamProvider.station(code: code)
    }
}
