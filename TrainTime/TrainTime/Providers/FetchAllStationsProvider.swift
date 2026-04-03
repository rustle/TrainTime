protocol FetchAllStationsProvider: Sendable {
    func fetchStations() async throws -> [Station]
}

extension APIService: FetchAllStationsProvider {}
