import Foundation
import Testing
@testable import TrainTime

// MARK: - Fixtures

private func row(_ code: String,
                 _ name: String?,
                 _ city: String?) -> StationRow {
    StationRow(station: Station(name: name,
                                code: code,
                                city: city,
                                trainIdentifiers: []))
}

/// Real stations from the Amtrak `stations.json` fixture, chosen to cover
/// hyphens, slashes, periods, apostrophes, diacritics, abbreviations, and
/// cities that differ from station names.
private let fixtureRows: [StationRow] = [
    row("NYP", "New York Penn", "New York"),
    row("NYF", "New York State Fair", "Syracuse"),
    row("SYR", "Syracuse", "Syracuse"),
    row("NWK", "Newark Penn", "Newark"),
    row("NRK", "Newark", "Newark"),
    row("BAL", "Baltimore Penn", "Baltimore"),
    row("PNK", "Pennsauken", "Pennsauken"),
    row("PENN", "Penny", nil),
    row("WAS", "Washington Union", "Washington"),
    row("CHI", "Chicago Union", "Chicago"),
    row("CIC", "Chico", "Chico"),
    row("PHL", "Philadelphia 30th Street", "Philadelphia"),
    row("PHN", "Philadelphia North", "Philadelphia"),
    row("PGH", "Pittsburgh", "Pittsburgh"),
    row("PIT", "Pittsfield", "Pittsfield"),
    row("ACA", "Antioch-Pittsburg", "Antioch"),
    row("STL", "St. Louis Gateway", "St. Louis"),
    row("BAS", "Bay St. Louis", "Bay St. Louis"),
    row("SLAM", "Saint-Lambert", "St-Lambert"),
    row("SFOY", "Sainte-Foy", nil),
    row("FTL", "Fort Lauderdale", "Fort Lauderdale"),
    row("FTW", "Fort Worth", "Fort Worth"),
    row("WIP", "Fraser-Winter Park", "Fraser"),
    row("WPK", "Winter Park", "Winter Park"),
    row("WPR", "Winter Park Resort", "Winter Park"),
    row("WTH", "Winter Haven", "Winter Haven"),
    row("BNL", "Bloomington-Normal", "Normal"),
    row("MET", "Metropark", "Iselin"),
    row("LEE", "Lee's Summit", "Lee's Summit"),
    row("ODAY", "O'Day", nil),
    row("HMI", "Hammond/Whiting", "Hammond"),
    row("SPRJ", "Springhill Jct.", nil),
    row("PJC", "Princeton Junction", "Princeton Junction"),
    row("WNM", "Windsor-Mt. Ascutney", "Windsor"),
    row("MTP", "Mount Pleasant", "Mount Pleasant"),
    row("BOS", "Boston South", "Boston"),
    row("BON", "Boston North", "Boston"),
    row("BBY", "Boston Back Bay", "Boston"),
    row("RTE", "Westwood-Route 128", "Westwood"),
    row("GMRE", "Grand-Mère", nil),
    row("LAX", "Los Angeles Union", "Los Angeles"),
    row("SEA", "Seattle King Street", "Seattle"),
    row("MSP", "St. Paul - Minneapolis Union", "St. Paul"),
    row("SPG", "Springfield", "Springfield"),
    row("TRTO", "Toronto Union", "Toronto"),
    row("NFL", "Niagara Falls", "Niagara Falls"),
    row("CHS", "Charleston", "North Charleston"),
    row("NOL", "New Orleans", "New Orleans"),
    row("NHV", "New Haven Union", "New Haven"),
    row("DEN", "Denver", "Denver"),
    row("XYZ", nil, nil),
]

private func codes(_ query: String,
                   in rows: [StationRow] = fixtureRows) -> [String] {
    rows.search(query: query).map(\.station.code)
}

private func token(_ string: String) -> StationSearch.Token {
    StationSearch.Token(string.utf8)
}

private struct FixtureStation: Decodable {
    let code: String
    let name: String?
    let city: String?
}

/// The full Amtrak station fixture from the sibling `Amtrak` package when
/// the source tree is available, for realistic timing.
private func fullFixtureRows() -> [StationRow]? {
    var directory = URL(fileURLWithPath: #filePath)
    for _ in 0..<10 {
        directory.deleteLastPathComponent()
        let candidate = directory.appending(path: "Amtrak/Tests/AmtrakTests/Fixtures/stations.json")
        guard let data = try? Data(contentsOf: candidate),
              let stations = try? JSONDecoder().decode([String: FixtureStation].self, from: data) else {
            continue
        }
        return stations.values
            .sorted { $0.code < $1.code }
            .map { row($0.code, $0.name, $0.city) }
    }
    return nil
}

// MARK: - Tokenizing

struct StationSearchTokenizerTests {
    @Test func splitsOnPunctuationAndWhitespace() {
        #expect(StationSearch.tokens(in: "st. louis gateway") == [token("st"), token("louis"), token("gateway")])
        #expect(StationSearch.tokens(in: "fraser-winter park") == [token("fraser"), token("winter"), token("park")])
        #expect(StationSearch.tokens(in: "hammond/whiting") == [token("hammond"), token("whiting")])
        #expect(StationSearch.tokens(in: "st. paul - minneapolis union") == [token("st"), token("paul"), token("minneapolis"), token("union")])
        #expect(StationSearch.tokens(in: "westwood-route 128") == [token("westwood"), token("route"), token("128")])
    }

    @Test func dropsApostrophes() {
        #expect(StationSearch.tokens(in: "lee's summit") == [token("lees"), token("summit")])
        #expect(StationSearch.tokens(in: "o'day") == [token("oday")])
        #expect(StationSearch.tokens(in: "o\u{2019}day") == [token("oday")])
    }

    @Test func ignoresLeadingTrailingAndRepeatedSeparators() {
        #expect(StationSearch.tokens(in: "  new   york -- penn  ") == [token("new"), token("york"), token("penn")])
        #expect(StationSearch.tokens(in: " - . / ").isEmpty)
        #expect(StationSearch.tokens(in: "").isEmpty)
    }

    @Test func fieldsDeriveJoinedAndInitialsForMultiWordText() {
        let field = StationSearch.Field(text: "washington union")
        #expect(field.words.map(\.primary) == [token("washington"), token("union")])
        #expect(field.joined == token("washingtonunion"))
        #expect(field.initials == token("wu"))
        let single = StationSearch.Field(text: "denver")
        #expect(single.joined.isEmpty)
        #expect(single.initials.isEmpty)
    }

    @Test func abbreviationsAliasBothDirections() {
        let saint = StationSearch.Field(text: "saint-lambert")
        #expect(saint.words.first?.aliases == [token("st")])
        let abbreviated = StationSearch.Field(text: "st. louis")
        #expect(abbreviated.words.first?.aliases == [token("saint"), token("street")])
        let fort = StationSearch.Field(text: "fort worth")
        #expect(fort.words.first?.aliases == [token("ft")])
    }

    @Test func queryBoundsEditsByTokenLength() {
        #expect(StationSearch.maxEdits(forLength: 1) == 0)
        #expect(StationSearch.maxEdits(forLength: 3) == 0)
        #expect(StationSearch.maxEdits(forLength: 4) == 1)
        #expect(StationSearch.maxEdits(forLength: 7) == 1)
        #expect(StationSearch.maxEdits(forLength: 8) == 2)
        #expect(StationSearch.maxEdits(forLength: 14) == 2)
        let query = StationSearch.Query("NYP Philadelphia")
        #expect(query.terms.map(\.token) == [token("nyp"), token("philadelphia")])
        #expect(query.terms.map(\.maxEdits) == [0, 2])
    }
}

// MARK: - Edit distance

struct StationSearchEditDistanceTests {
    @Test func countsEachEditKindOnce() {
        #expect(StationSearch.prefixEditDistance(token("chicgo"), token("chicago"), limit: 1) == 1)
        #expect(StationSearch.prefixEditDistance(token("philadelpia"), token("philadelphia"), limit: 2) == 1)
        #expect(StationSearch.prefixEditDistance(token("chicagoo"), token("chicago"), limit: 1) == 1)
        #expect(StationSearch.prefixEditDistance(token("chicaho"), token("chicago"), limit: 1) == 1)
        #expect(StationSearch.prefixEditDistance(token("wahsington"), token("washington"), limit: 2) == 1)
    }

    @Test func editsAtTheStartOfTheWordStillMatch() {
        #expect(StationSearch.prefixEditDistance(token("hpiladelphia"), token("philadelphia"), limit: 2) == 1)
        #expect(StationSearch.prefixEditDistance(token("xhicago"), token("chicago"), limit: 1) == 1)
        #expect(StationSearch.prefixEditDistance(token("hicago"), token("chicago"), limit: 1) == 1)
        #expect(StationSearch.prefixEditDistance(token("cchicago"), token("chicago"), limit: 1) == 1)
        #expect(StationSearch.prefixEditDistance(token("xxicago"), token("chicago"), limit: 2) == 2)
        #expect(StationSearch.prefixEditDistance(token("xxicago"), token("chicago"), limit: 1) == nil)
    }

    @Test func matchesPrefixesOfLongerWords() {
        #expect(StationSearch.prefixEditDistance(token("pitt"), token("pittsburgh"), limit: 1) == 0)
        #expect(StationSearch.prefixEditDistance(token("pittsbrg"), token("pittsburgh"), limit: 1) == 1)
    }

    @Test func returnsNilBeyondLimit() {
        #expect(StationSearch.prefixEditDistance(token("boston"), token("austin"), limit: 2) == nil)
        #expect(StationSearch.prefixEditDistance(token("philadelpia"), token("philadelphia"), limit: 0) == nil)
        #expect(StationSearch.prefixEditDistance(token("chicgo"), token("chico"), limit: 0) == nil)
        #expect(StationSearch.prefixEditDistance(token("zzzz"), token("york"), limit: 2) == nil)
    }
}

// MARK: - Search behavior

struct StationSearchTests {
    @Test(arguments: ["", " ", "\t\n", " - / . "])
    func emptyOrSeparatorOnlyQueryReturnsEverythingUnfiltered(query: String) {
        #expect(fixtureRows.search(query: query) == fixtureRows)
    }

    @Test(arguments: ["penn new york", "york penn", "ny penn", "new york penn", "NEW YORK PENN", "penn NY"])
    func termsMatchInAnyOrderAcrossFields(query: String) {
        #expect(codes(query) == ["NYP"])
    }

    @Test func everyTermMustMatch() {
        #expect(codes("boston north") == ["BON"])
        #expect(codes("new york") == ["NYP", "NYF"])
        #expect(codes("york boston").isEmpty)
        #expect(codes("winter park fraser") == ["WIP"])
    }

    @Test func termsMayMatchDifferentFields() {
        #expect(codes("iselin metro") == ["MET"])
        #expect(codes("normal bloom") == ["BNL"])
        #expect(codes("syracuse fair") == ["NYF"])
    }

    @Test(arguments: [
        ("st louis", "STL"),
        ("st. louis", "STL"),
        ("saint louis", "STL"),
        ("ft lauderdale", "FTL"),
        ("fort lauderdale", "FTL"),
        ("ft laud", "FTL"),
        ("mt ascutney", "WNM"),
        ("mount ascutney", "WNM"),
        ("mt pleasant", "MTP"),
        ("st lambert", "SLAM"),
        ("ste foy", "SFOY"),
        ("sainte foy", "SFOY"),
        ("lees summit", "LEE"),
        ("lee's summit", "LEE"),
        ("lee's", "LEE"),
        ("oday", "ODAY"),
        ("o'day", "ODAY"),
        ("whiting", "HMI"),
        ("hammond", "HMI"),
        ("route 128", "RTE"),
        ("128", "RTE"),
        ("grand mere", "GMRE"),
        ("GRAND MÈRE", "GMRE"),
        ("grand-mère", "GMRE"),
        ("fraser", "WIP"),
        ("minneapolis", "MSP"),
    ])
    func punctuationAndAbbreviationsAreForgiven(query: String,
                                                expected: String) {
        #expect(codes(query).first == expected, "\(query)")
    }

    @Test func abbreviationsMatchBothWays() {
        #expect(codes("junction").contains("SPRJ"))
        #expect(codes("junction").contains("PJC"))
        #expect(codes("jct").contains("SPRJ"))
        #expect(codes("jct").contains("PJC"))
        #expect(codes("n charleston") == ["CHS"])
        #expect(codes("north charleston") == ["CHS"])
    }

    @Test func hyphenatedNamesMatchEveryPart() {
        #expect(codes("winter park") == ["WPK", "WPR", "WIP"])
        #expect(codes("winter") == ["WTH", "WPK", "WPR", "WIP"])
        #expect(codes("pittsburg") == ["PGH", "ACA"])
    }

    @Test func queriesTypedWithoutSpacesMatchJoinedWords() {
        #expect(codes("newyork") == ["NYP", "NYF"])
        #expect(codes("stlouis") == ["STL"])
        #expect(codes("winterpark") == ["WPK", "WPR"])
    }

    @Test func initialsMatchMultiWordNames() {
        #expect(codes("wu") == ["WAS"])
        #expect(codes("lau") == ["FTL", "LAX"])
    }

    @Test(arguments: [
        ("philadelpia", ["PHL", "PHN"]),
        ("chicgo", ["CHI", "CIC"]),
        ("pitsburgh", ["PGH", "ACA"]),
        ("wahsington", ["WAS"]),
        ("bostn south", ["BOS"]),
        ("sprngfield", ["SPG"]),
    ])
    func typosStillMatch(query: String,
                         expected: [String]) {
        #expect(codes(query) == expected, "\(query)")
    }

    @Test func typosRankBelowDirectMatches() {
        #expect(codes("chico") == ["CIC", "CHI"])
        #expect(codes("newark") == ["NRK", "NWK"])
        #expect(codes("nework") == ["NRK", "NWK"])
    }

    @Test func shortTokensAndCodesAreNotFuzzy() {
        #expect(codes("nyq").isEmpty)
        #expect(codes("wsa").isEmpty)
        #expect(codes("nypp").isEmpty)
        #expect(codes("dne").isEmpty)
        #expect(codes("PGH") == ["PGH"])
    }

    @Test func exactCodeRanksFirstThenCodePrefixThenName() {
        #expect(codes("nyp") == ["NYP"])
        #expect(codes("ny") == ["NYP", "NYF"])
        #expect(codes("pit") == ["PIT", "PGH", "ACA"])
        #expect(codes("den") == ["DEN"])
        #expect(codes("xyz") == ["XYZ"])
    }

    @Test func nameStartBeatsLaterWordBeatsCity() {
        #expect(codes("penn") == ["PENN", "PNK", "BAL", "NWK", "NYP"])
        #expect(codes("syracuse") == ["SYR", "NYF"])
        #expect(codes("normal") == ["BNL"])
        #expect(codes("iselin") == ["MET"])
        // Second-word matches tie and sort by title; third- and fourth-word matches follow.
        #expect(codes("union") == ["CHI", "TRTO", "WAS", "LAX", "NHV", "MSP"])
    }

    @Test func wholeWordMatchesRankAboveLongerWords() {
        #expect(codes("boston") == ["BBY", "BON", "BOS"])
        #expect(codes("winter haven") == ["WTH"])
        #expect(codes("newark penn") == ["NWK"])
    }

    @Test func resultsAreDeterministic() {
        let shuffled = Array(fixtureRows.reversed())
        for query in ["penn", "st louis", "new york", "union", "philadelpia", "b"] {
            #expect(codes(query, in: shuffled) == codes(query), "\(query)")
        }
    }

    @Test func fullQueryScoresEveryTerm() {
        let query = StationSearch.Query("new york penn")
        guard let nyp = fixtureRows.first(where: { $0.station.code == "NYP" }),
              let nyf = fixtureRows.first(where: { $0.station.code == "NYF" }) else {
            Issue.record("Missing fixture rows")
            return
        }
        #expect(StationSearch.score(query: query, document: nyp.searchDocument) != nil)
        #expect(StationSearch.score(query: query, document: nyf.searchDocument) == nil)
    }

    @Test func fullSetSearchIsFast() {
        let rows = fullFixtureRows() ?? (0..<12).flatMap { index in
            fixtureRows.map { row("\($0.station.code)\(index)", $0.station.name, $0.station.city) }
        }
        let queries = ["p", "phil", "st louis", "new york penn", "wahsington", "chicgo union", "winter park"]
        for query in queries {
            _ = rows.search(query: query)
        }
        let iterations = 50
        let clock = ContinuousClock()
        var slowest: Duration = .zero
        var total: Duration = .zero
        for query in queries {
            let elapsed = clock.measure {
                for _ in 0..<iterations {
                    _ = rows.search(query: query)
                }
            }
            let perQuery = elapsed / iterations
            slowest = max(slowest, perQuery)
            total += perQuery
            print("StationSearch: \"\(query)\" \(perQuery) per query")
        }
        let average = total / queries.count
        print("StationSearch: \(rows.count) rows, average \(average) per query, slowest \(slowest)")
        // Debug builds run unoptimized (roughly 5 ms here); an -O build of the
        // same code measures well under 1 ms, so this only catches large regressions.
        #expect(slowest < .milliseconds(50))
    }
}
