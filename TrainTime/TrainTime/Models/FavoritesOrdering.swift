import Foundation

/// A favorite station's place in the user's order. `sortOrder` is nil for
/// favorites written before the app tracked order.
struct FavoritePosition: Equatable, Sendable {
    let code: String
    let sortOrder: Double?
}

/// One station's user data as the app wants it written. A nil `isFavorite`
/// unfavorites; `sortOrder` only means anything for favorites.
struct StationUserDataChange: Hashable, Sendable {
    let code: String
    let isFavorite: Bool?
    let sortOrder: Double?
}

/// Works out what to write when favorites are added or moved.
///
/// Positions are sparse doubles rather than a dense 0...n index. Moving one
/// station writes one row: its new position is the midpoint between its new
/// neighbours. That matters because favorites sync per station with
/// last-writer-wins, so a move on one device and a move on another touch
/// different records and both survive the merge. Dense indexing would rewrite
/// every favorite on each move and the merge would interleave two devices'
/// numberings.
///
/// Doubles run out of distinguishable midpoints after ~50 moves into the same
/// gap, so when a gap gets too tight, or when any favorite has no position yet,
/// every favorite is reindexed with `spacing` between neighbours. Ties are
/// broken by station code everywhere, so order is deterministic even if two
/// devices assign the same position.
enum FavoritesOrdering {
    /// Distance between neighbours when positions are assigned from scratch.
    static let spacing: Double = 1
    /// Gaps narrower than this trigger a reindex instead of another midpoint.
    static let minimumGap: Double = 1e-6

    /// The favorites as the list shows them: ordered ones by position, then
    /// ones without a position in the order given (the list gives them by name).
    static func displayOrder(_ favorites: [FavoritePosition]) -> [FavoritePosition] {
        var positioned: [(position: Double, favorite: FavoritePosition)] = []
        var unpositioned: [FavoritePosition] = []
        for favorite in favorites {
            if let sortOrder = favorite.sortOrder {
                positioned.append((sortOrder, favorite))
            } else {
                unpositioned.append(favorite)
            }
        }
        positioned.sort { lhs, rhs in
            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }
            return lhs.favorite.code < rhs.favorite.code
        }
        return positioned.map(\.favorite) + unpositioned
    }

    /// What to write so `order` becomes the persisted order, given the codes
    /// the person actually `moved`. Only moved favorites get new positions,
    /// unless a reindex is needed, in which case every favorite is returned.
    static func changes(for order: [FavoritePosition],
                        moved: Set<String>) -> [StationUserDataChange] {
        guard !moved.isEmpty else {
            return []
        }
        // Unmoved favorites are the fixed points. They must all have positions
        // that strictly increase in list order, or there is nothing to fit
        // the moved ones between.
        var anchors: [Double?] = []
        var lastAnchor: Double?
        for favorite in order {
            guard !moved.contains(favorite.code) else {
                anchors.append(nil)
                continue
            }
            guard let sortOrder = favorite.sortOrder else {
                return reindex(order)
            }
            if let lastAnchor, sortOrder <= lastAnchor {
                return reindex(order)
            }
            lastAnchor = sortOrder
            anchors.append(sortOrder)
        }
        var changes: [StationUserDataChange] = []
        var index = 0
        while index < order.count {
            guard anchors[index] == nil else {
                index += 1
                continue
            }
            // A run of moved favorites between two anchors (or an edge).
            let runStart = index
            while index < order.count, anchors[index] == nil {
                index += 1
            }
            let runCount = index - runStart
            let lower = runStart > 0 ? anchors[runStart - 1] : nil
            let upper = index < order.count ? anchors[index] : nil
            let positions: [Double]
            switch (lower, upper) {
            case (nil, nil):
                return reindex(order)
            case let (lower?, nil):
                positions = (1...runCount).map { lower + spacing * Double($0) }
            case let (nil, upper?):
                positions = (1...runCount).reversed().map { upper - spacing * Double($0) }
            case let (lower?, upper?):
                let step = (upper - lower) / Double(runCount + 1)
                guard step >= minimumGap else {
                    return reindex(order)
                }
                positions = (1...runCount).map { lower + step * Double($0) }
            }
            for (offset, position) in positions.enumerated() {
                changes.append(StationUserDataChange(code: order[runStart + offset].code,
                                                     isFavorite: true,
                                                     sortOrder: position))
            }
        }
        return changes
    }

    /// What to write to add `code` after the last of `favorites`, which are
    /// expected in display order. Reindexes when any favorite lacks a
    /// position so the new one really lands last.
    static func changes(adding code: String,
                        to favorites: [FavoritePosition]) -> [StationUserDataChange] {
        let others = favorites.filter { $0.code != code }
        guard others.allSatisfy({ $0.sortOrder != nil }) else {
            return reindex(others + [FavoritePosition(code: code, sortOrder: nil)])
        }
        let last = others.compactMap(\.sortOrder).max()
        return [StationUserDataChange(code: code,
                                      isFavorite: true,
                                      sortOrder: last.map { $0 + spacing } ?? 0)]
    }

    /// What to write to unfavorite `code`. The position goes too, so
    /// refavoriting lands at the end rather than wherever it used to be.
    static func changeRemoving(_ code: String) -> StationUserDataChange {
        StationUserDataChange(code: code,
                              isFavorite: nil,
                              sortOrder: nil)
    }

    private static func reindex(_ order: [FavoritePosition]) -> [StationUserDataChange] {
        order.enumerated().map { index, favorite in
            StationUserDataChange(code: favorite.code,
                                  isFavorite: true,
                                  sortOrder: spacing * Double(index))
        }
    }
}

extension Array where Element == Station {
    /// Favorites first in the user's order, then favorites that have no order
    /// yet as given, then everything else as given.
    func orderedFavoritesFirst() -> [Station] {
        var favorites: [Station] = []
        var others: [Station] = []
        for station in self {
            if station.isFavorite == true {
                favorites.append(station)
            } else {
                others.append(station)
            }
        }
        let byCode = Dictionary(favorites.map { ($0.code, $0) },
                                uniquingKeysWith: { first, _ in first })
        let order = FavoritesOrdering.displayOrder(favorites.map {
            FavoritePosition(code: $0.code,
                             sortOrder: $0.favoriteSortOrder)
        })
        return order.compactMap { byCode[$0.code] } + others
    }
}
