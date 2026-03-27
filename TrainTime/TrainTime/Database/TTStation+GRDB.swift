import Foundation
import GRDB

extension TTStation: TableRecord {
    static let databaseTableName = "station"
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
        static let formattedPostalAddress = Column("formattedPostalAddress")
        // Used in init(row:) and to annotate an isFavorite column during fetch
        // Not used in encode because it's persisted in it's own table/db
        // See also StationUserData.Columns.isFavorite
        static let isFavorite = Column("isFavorite")
    }
}

extension TTStation: Identifiable {
    var id: String {
        code
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
        formattedPostalAddress = row[Columns.formattedPostalAddress]
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
        container[Columns.formattedPostalAddress] = formattedPostalAddress
        container[Columns.trainIdentifiers] = try JSONEncoder().encode(trainIdentifiers)
        container[Columns.normalizedCode] = normalizedCode
        container[Columns.normalizedName] = normalizedName
        container[Columns.normalizedCity] = normalizedCity
    }
}
