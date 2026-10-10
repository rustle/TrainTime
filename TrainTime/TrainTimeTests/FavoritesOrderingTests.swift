import Foundation
import Testing
@testable import TrainTime

private func position(_ code: String,
                      _ sortOrder: Double?) -> FavoritePosition {
    FavoritePosition(code: code,
                     sortOrder: sortOrder)
}

private func change(_ code: String,
                    _ sortOrder: Double?) -> StationUserDataChange {
    StationUserDataChange(code: code,
                          isFavorite: true,
                          sortOrder: sortOrder)
}

struct FavoritesOrderingTests {
    // MARK: Display order
    @Test func displayOrderPutsOrderedFavoritesFirstThenTheRestAsGiven() {
        let order = FavoritesOrdering.displayOrder([position("UCA", nil),
                                                    position("SYR", 2),
                                                    position("ALB", nil),
                                                    position("ROC", 1)])
        #expect(order.map(\.code) == ["ROC", "SYR", "UCA", "ALB"])
    }
    @Test func displayOrderBreaksTiesByCode() {
        let order = FavoritesOrdering.displayOrder([position("UCA", 1),
                                                    position("ROC", 1)])
        #expect(order.map(\.code) == ["ROC", "UCA"])
    }
    // MARK: Moving
    @Test func movingBetweenNeighboursWritesOnlyTheMovedStation() {
        let changes = FavoritesOrdering.changes(for: [position("UCA", 0),
                                                      position("SYR", 2),
                                                      position("ROC", 1)],
                                                moved: ["SYR"])
        #expect(changes == [change("SYR", 0.5)])
    }
    @Test func movingToTheTopGoesOneSpacingAboveTheFirst() {
        let changes = FavoritesOrdering.changes(for: [position("SYR", 2),
                                                      position("UCA", 0),
                                                      position("ROC", 1)],
                                                moved: ["SYR"])
        #expect(changes == [change("SYR", -1)])
    }
    @Test func movingToTheBottomGoesOneSpacingBelowTheLast() {
        let changes = FavoritesOrdering.changes(for: [position("ROC", 1),
                                                      position("SYR", 2),
                                                      position("UCA", 0)],
                                                moved: ["UCA"])
        #expect(changes == [change("UCA", 3)])
    }
    @Test func movingSeveralSharesTheGapEvenly() {
        let changes = FavoritesOrdering.changes(for: [position("UCA", 0),
                                                      position("ALB", 5),
                                                      position("SYR", 6),
                                                      position("ROC", 4)],
                                                moved: ["ALB", "SYR"])
        #expect(changes == [change("ALB", 4.0 / 3.0),
                            change("SYR", 8.0 / 3.0)])
    }
    @Test func nothingMovedWritesNothing() {
        #expect(FavoritesOrdering.changes(for: [position("UCA", 0)],
                                          moved: []).isEmpty)
    }
    @Test func favoritesWithoutPositionsAreReindexedOnFirstMove() {
        let changes = FavoritesOrdering.changes(for: [position("SYR", nil),
                                                      position("UCA", nil),
                                                      position("ROC", nil)],
                                                moved: ["SYR"])
        #expect(changes == [change("SYR", 0),
                            change("UCA", 1),
                            change("ROC", 2)])
    }
    @Test func tooTightAGapReindexesEverything() {
        let changes = FavoritesOrdering.changes(for: [position("UCA", 0),
                                                      position("SYR", 5),
                                                      position("ROC", 1e-9)],
                                                moved: ["SYR"])
        #expect(changes == [change("UCA", 0),
                            change("SYR", 1),
                            change("ROC", 2)])
    }
    @Test func duplicatePositionsFromAMergeReindexEverything() {
        let changes = FavoritesOrdering.changes(for: [position("ROC", 1),
                                                      position("SYR", 2),
                                                      position("UCA", 1)],
                                                moved: ["SYR"])
        #expect(changes == [change("ROC", 0),
                            change("SYR", 1),
                            change("UCA", 2)])
    }
    @Test func movingEveryFavoriteReindexesEverything() {
        let changes = FavoritesOrdering.changes(for: [position("ROC", 1),
                                                      position("UCA", 0)],
                                                moved: ["ROC", "UCA"])
        #expect(changes == [change("ROC", 0),
                            change("UCA", 1)])
    }
    // MARK: Adding and removing
    @Test func addingAppendsAfterTheLast() {
        let changes = FavoritesOrdering.changes(adding: "ALB",
                                                to: [position("UCA", 0),
                                                     position("ROC", 2.5)])
        #expect(changes == [change("ALB", 3.5)])
    }
    @Test func addingTheFirstFavoriteStartsAtZero() {
        #expect(FavoritesOrdering.changes(adding: "ALB", to: []) == [change("ALB", 0)])
    }
    @Test func addingToFavoritesWithoutPositionsReindexesThemFirst() {
        let changes = FavoritesOrdering.changes(adding: "ALB",
                                                to: [position("UCA", nil),
                                                     position("ROC", 3)])
        #expect(changes == [change("UCA", 0),
                            change("ROC", 1),
                            change("ALB", 2)])
    }
    @Test func removingDropsTheFavoriteAndItsPosition() {
        #expect(FavoritesOrdering.changeRemoving("UCA") == StationUserDataChange(code: "UCA",
                                                                                  isFavorite: nil,
                                                                                  sortOrder: nil))
    }
    // MARK: Stations
    @Test func stationsAreOrderedFavoritesFirstInUserOrder() {
        func station(_ fixture: TrainTime.Station,
                     favorite sortOrder: Double??) -> TrainTime.Station {
            var station = fixture
            if let sortOrder {
                station.isFavorite = true
                station.favoriteSortOrder = sortOrder
            }
            return station
        }
        // As the database hands them over: by name.
        let byName = [station(.nypFixture, favorite: nil),
                      station(.rocFixture, favorite: .some(nil)),
                      station(.syrFixture, favorite: 1),
                      station(.ucaFixture, favorite: 0)]
        #expect(byName.orderedFavoritesFirst().map(\.code) == ["UCA", "SYR", "ROC", "NYP"])
    }
    // MARK: Array.moving
    @Test func movingMatchesSwiftUIOffsets() {
        let letters = ["a", "b", "c", "d"]
        #expect(letters.moving(fromOffsets: [0], toOffset: 4) == ["b", "c", "d", "a"])
        #expect(letters.moving(fromOffsets: [3], toOffset: 0) == ["d", "a", "b", "c"])
        #expect(letters.moving(fromOffsets: [1], toOffset: 3) == ["a", "c", "b", "d"])
        #expect(letters.moving(fromOffsets: [0, 2], toOffset: 4) == ["b", "d", "a", "c"])
        #expect(letters.moving(fromOffsets: [1], toOffset: 1) == letters)
    }
}
