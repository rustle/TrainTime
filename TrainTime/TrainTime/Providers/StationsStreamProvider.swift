import AsyncAlgorithms
import GRDB

protocol StationsStreamProvider: Sendable {
    func stations() async throws -> any AsyncThrowingSendableSequence<[Station]>
}

extension DatabasePool {
    fileprivate func stationFavorites() -> AsyncValueObservation<[FavoritePosition]> {
        ValueObservation
            .tracking { db in
                try StationUserData
                    .filter(StationUserData.Columns.isFavorite == true)
                    .order(StationUserData.Columns.code)
                    .fetchAll(db)
                    .map { FavoritePosition(code: $0.code,
                                            sortOrder: $0.sortOrder) }
            }
            .values(in: self)
    }
    fileprivate func stations(favorites: [FavoritePosition]) -> AsyncValueObservation<[Station]> {
        let code = Station.Columns.code
        let isFavorite = Station.Columns.isFavorite
        let favoriteCodes = favorites.map(\.code)
        let isFavoriteAlias = SQL("(CASE WHEN \(code) IN \(favoriteCodes) THEN 1 ELSE NULL END) AS \(isFavorite)")
        let sortOrders = Dictionary(favorites.map { ($0.code, $0.sortOrder) },
                                    uniquingKeysWith: { first, _ in first })
        return ValueObservation
            .tracking { db in
                try Station
                    .annotated(with: [isFavoriteAlias])
                    .order(
                        coalesce([
                            Station.Columns.normalizedName,
                            Station.Columns.normalizedCode
                        ])
                            .asc
                    )
                    .fetchAll(db)
                    .map { station in
                        var station = station
                        station.favoriteSortOrder = sortOrders[station.code] ?? nil
                        return station
                    }
                    // Favorites live in another database, so their order is
                    // applied here rather than in SQL.
                    .orderedFavoritesFirst()
            }
            .values(in: self)
    }
}

struct StationsStreamDatabaseProvider: StationsStreamProvider {
    let cacheConnection: DatabasePool
    let userDataConnection: DatabasePool
    func stations() async throws -> any AsyncThrowingSendableSequence<[Station]> {
        userDataConnection
            .stationFavorites()
            .flatMapLatest { [cacheConnection] favorites in
                cacheConnection
                    .stations(favorites: favorites)
            }
    }
}
