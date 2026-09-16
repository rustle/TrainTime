import Foundation
import GRDB

struct StationUserData: Sendable {
    let code: String
    var isFavorite: Bool?
    /// When `isFavorite` last changed. Nil for rows written before the app
    /// tracked it; cloud sync treats those as local-only until it stamps them.
    var updatedAt: Date?
    init(code: String,
         isFavorite: Bool?,
         updatedAt: Date? = nil) {
        self.code = code
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }
}

extension StationUserData: TableRecord {
    static let databaseTableName = "station"
    enum Columns {
        static let code = Column("code")
        // See also Station.Columns.isFavorite
        static let isFavorite = Column("isFavorite")
        static let updatedAt = Column("updatedAt")
    }
}

extension StationUserData: Identifiable {
    var id: String { code }
}

extension StationUserData: FetchableRecord {
    init(row: Row) throws {
        code = row[Columns.code]
        isFavorite = row[Columns.isFavorite]
        updatedAt = row[Columns.updatedAt]
    }
}

extension StationUserData: PersistableRecord {
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.code] = code
        container[Columns.isFavorite] = isFavorite
        container[Columns.updatedAt] = updatedAt
    }
}
