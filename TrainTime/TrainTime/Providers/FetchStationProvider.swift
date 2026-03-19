protocol FetchStationProvider: Sendable {
    func fetchStation(id: String) async throws -> TTStation
}

extension APIService: FetchStationProvider {}
