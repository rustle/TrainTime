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
    /// Fetches and persists the station, returning the freshly fetched value so
    /// callers don't have to wait for the database observation to catch up.
    @discardableResult
    func load(stationCode: String) async throws -> Station {
        let station = try await fetchStationProvider.fetchStation(code: stationCode)
        try await writeStationProvider.writeStation(station)
        return station
    }
    func station(code: String) async throws -> any AsyncThrowingSendableSequence<Station?> {
        try await stationStreamProvider.station(code: code)
    }
}
