protocol FetchStationProvider: Sendable {
    func fetchStation(code: String) async throws -> Station
}

extension APIService: FetchStationProvider {}
