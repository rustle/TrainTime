extension TTStationResponse {
    func sortedRows() -> [StationRow] {
        reduce(into: []) { accumulator, element in
            accumulator.sortedInsert(StationRow(station: element.value))
        }
    }
}
