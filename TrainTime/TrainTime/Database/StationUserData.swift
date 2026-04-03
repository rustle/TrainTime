import GRDB

struct StationUserData: Sendable {
    let code: String
    var isFavorite: Bool?
}

extension StationUserData: TableRecord {
    static let databaseTableName = "station"
    enum Columns {
        static let code = Column("code")
        // See also Station.Columns.isFavorite
        static let isFavorite = Column("isFavorite")
    }
}

extension StationUserData: Identifiable {
    var id: String { code }
}

extension StationUserData: FetchableRecord {
    init(row: Row) throws {
        code = row[Columns.code]
        isFavorite = row[Columns.isFavorite]
    }
}

extension StationUserData: PersistableRecord {
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.code] = code
        container[Columns.isFavorite] = isFavorite
    }
}
