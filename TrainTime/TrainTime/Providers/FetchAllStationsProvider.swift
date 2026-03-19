protocol FetchAllStationsProvider: Sendable {
    func fetchAllStations() async throws -> TTStationResponse
}

extension APIService: FetchAllStationsProvider {}
