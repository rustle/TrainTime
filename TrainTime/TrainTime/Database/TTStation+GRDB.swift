import Foundation
import GRDB

extension TTStation: TableRecord {
    static let databaseTableName = "station"
}

extension TTStation {
    enum Columns {
        static let code = Column("code")
        static let name = Column("name")
        static let tz = Column("tz")
        static let lat = Column("lat")
        static let lon = Column("lon")
        static let address1 = Column("address1")
        static let address2 = Column("address2")
        static let city = Column("city")
        static let zip = Column("zip")
        static let trainIdentifiers = Column("trainIdentifiers")
        static let normalizedCode = Column("normalizedCode")
        static let normalizedName = Column("normalizedName")
        static let normalizedCity = Column("normalizedCity")
        static let isFavorite = Column("isFavorite")
    }
}

extension TTStation: FetchableRecord {
    init(row: Row) throws {
        code = row[Columns.code]
        name = row[Columns.name]
        tz = row[Columns.tz]
        lat = row[Columns.lat]
        lon = row[Columns.lon]
        address1 = row[Columns.address1]
        address2 = row[Columns.address2]
        city = row[Columns.city]
        zip = row[Columns.zip]
        trainIdentifiers = try JSONDecoder().decode([String].self, from: row[Columns.trainIdentifiers])
        normalizedCode = row[Columns.normalizedCode]
        normalizedName = row[Columns.normalizedName]
        normalizedCity = row[Columns.normalizedCity]
        isFavorite = row[Columns.isFavorite]
    }
}

extension TTStation: PersistableRecord {
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.code] = code
        container[Columns.name] = name
        container[Columns.tz] = tz
        container[Columns.lat] = lat
        container[Columns.lon] = lon
        container[Columns.address1] = address1
        container[Columns.address2] = address2
        container[Columns.city] = city
        container[Columns.zip] = zip
        container[Columns.trainIdentifiers] = try JSONEncoder().encode(trainIdentifiers)
        container[Columns.normalizedCode] = normalizedCode
        container[Columns.normalizedName] = normalizedName
        container[Columns.normalizedCity] = normalizedCity
        if let isFavorite {
            container[Columns.isFavorite] = isFavorite
        }
    }
}
