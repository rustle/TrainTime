import AsyncAlgorithms
import GRDB

protocol StationsStreamProvider: Sendable {
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]>
}

extension DatabasePool {
    fileprivate func stationFavorites() -> AsyncValueObservation<[String]> {
        ValueObservation
            .tracking { db in
                try StationUserData
                    .filter(StationUserData.Columns.isFavorite == true)
                    .select(StationUserData.Columns.code)
                    .fetchAll(db)
            }
            .values(in: self)
    }
    fileprivate func stations(favorites: [String]) -> AsyncValueObservation<[TTStation]> {
        let code = TTStation.Columns.code
        let isFavorite = TTStation.Columns.isFavorite
        let isFavoriteAlias = SQL("(CASE WHEN \(code) IN \(favorites) THEN 1 ELSE NULL END) AS \(isFavorite)")
        let isFavoriteOrdering = favorites.contains(code).desc
        return ValueObservation
            .tracking { db in
                try TTStation
                    .annotated(with: [isFavoriteAlias])
                    .order(
                        isFavoriteOrdering,
                        coalesce([
                            TTStation.Columns.normalizedName,
                            TTStation.Columns.normalizedCode
                        ])
                            .asc
                    )
                    .fetchAll(db)
            }
            .values(in: self)
    }
}

struct StationsStreamDatabaseProvider: StationsStreamProvider {
    let cacheConnection: DatabasePool
    let userDataConnection: DatabasePool
    func stations() async throws -> any AsyncThrowingSendableSequence<[TTStation]> {
        userDataConnection
            .stationFavorites()
            .flatMapLatest { [cacheConnection] favorites in
                cacheConnection
                    .stations(favorites: favorites)
            }
    }
}
