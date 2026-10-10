import Foundation

/// Ranked, word-based station search that tolerates punctuation, common
/// abbreviations, and small typos.
///
/// Each `StationRow` folds and tokenizes its station once into a `Document`.
/// A query is tokenized once into `Query.Term`s, and every term must match
/// some part of a station (code, name, or city) for the station to be
/// included. The station's score is the sum of each term's best match, so a
/// station is never limited to a single field or bucket.
enum StationSearch {
    /// A folded word stored as UTF-8 bytes so prefix checks and edit
    /// distance work on plain integers without per-query String work.
    typealias Token = [UInt8]

    // MARK: - Index

    struct Word: Sendable {
        /// The word as written, folded.
        let primary: Token
        /// Abbreviation alternates ("st" for "saint", "saint" for "st").
        let aliases: [Token]
    }

    struct Field: Sendable {
        let words: [Word]
        /// Words run together so queries typed without spaces still match
        /// ("newyork"). Empty for fields with fewer than two words.
        let joined: Token
        /// First letter of each word ("wu" for "Washington Union"). Empty for
        /// fields with fewer than two words.
        let initials: Token
        static let empty = Field(text: nil)
        init(text: String?) {
            let tokens = text.map(StationSearch.tokens(in:)) ?? []
            words = tokens.map { Word(primary: $0, aliases: StationSearch.aliases[$0] ?? []) }
            if tokens.count >= 2 {
                joined = tokens.flatMap { $0 }
                initials = tokens.compactMap(\.first)
            } else {
                joined = []
                initials = []
            }
        }
    }

    struct Document: Sendable {
        let code: Token
        let name: Field
        let city: Field
        init(station: Station) {
            code = StationSearch.tokens(in: station.normalizedCode).flatMap { $0 }
            name = Field(text: station.normalizedName)
            city = Field(text: station.normalizedCity)
        }
    }

    // MARK: - Query

    struct Query: Sendable {
        struct Term: Sendable {
            let token: Token
            /// Edits allowed for a fuzzy match, bounded by token length so
            /// short tokens and station codes stay precise.
            let maxEdits: Int
        }
        let terms: [Term]
        var isEmpty: Bool {
            terms.isEmpty
        }
        init(_ text: String) {
            terms = StationSearch.tokens(in: text.normalized).map {
                Term(token: $0, maxEdits: StationSearch.maxEdits(forLength: $0.count))
            }
        }
    }

    static func maxEdits(forLength length: Int) -> Int {
        switch length {
        case ..<4:
            return 0
        case 4...7:
            return 1
        default:
            return 2
        }
    }

    // MARK: - Tokenizing

    /// Splits already-folded text into lowercase alphanumeric words.
    /// Apostrophes are dropped ("lee's" -> "lees"); every other
    /// non-alphanumeric character separates words, so "St. Louis",
    /// "Winter Park-Fraser", and "Hammond/Whiting" each split cleanly.
    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var current = Token()
        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = Token()
            }
        }
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                let byte = UInt8(truncatingIfNeeded: scalar.value)
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "z"):
                    current.append(byte)
                case UInt8(ascii: "A")...UInt8(ascii: "Z"):
                    current.append(byte | 0x20)
                case UInt8(ascii: "'"):
                    continue
                default:
                    flush()
                }
            } else if scalar == "\u{2019}" {
                continue
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                current.append(contentsOf: scalar.utf8)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static let abbreviationPairs: [(String, String)] = [
        ("st", "saint"),
        ("st", "street"),
        ("ste", "sainte"),
        ("ft", "fort"),
        ("mt", "mount"),
        ("pt", "port"),
        ("jct", "junction"),
        ("intl", "international"),
        ("sta", "station"),
        ("ctr", "center"),
        ("n", "north"),
        ("s", "south"),
        ("e", "east"),
        ("w", "west"),
    ]

    /// Alternate spellings keyed by folded word, built symmetrically so a
    /// query for either form finds a station written with the other.
    static let aliases: [Token: [Token]] = {
        var aliases: [Token: [Token]] = [:]
        aliases.reserveCapacity(abbreviationPairs.count)
        for (short, long) in abbreviationPairs {
            let short = Token(short.utf8)
            let long = Token(long.utf8)
            aliases[short, default: []].append(long)
            aliases[long, default: []].append(short)
        }
        return aliases
    }()

    // MARK: - Scoring

    /// Higher tiers are separated by more than any within-tier adjustment,
    /// so the tier order below is also the ranking order.
    private enum Tier {
        static let codeExact = 900
        static let codePrefix = 800
        static let nameStart = 700
        static let nameJoined = 690
        static let nameWord = 600
        static let nameInitials = 550
        static let cityStart = 500
        static let cityJoined = 490
        static let cityWord = 480
        static let cityInitials = 450
        static let nameFuzzy = 300
        static let cityFuzzy = 200
    }

    private struct FieldTiers {
        let start: Int
        let joined: Int
        let word: Int
        let initials: Int
        let fuzzy: Int
        static let name = FieldTiers(start: Tier.nameStart,
                                     joined: Tier.nameJoined,
                                     word: Tier.nameWord,
                                     initials: Tier.nameInitials,
                                     fuzzy: Tier.nameFuzzy)
        static let city = FieldTiers(start: Tier.cityStart,
                                     joined: Tier.cityJoined,
                                     word: Tier.cityWord,
                                     initials: Tier.cityInitials,
                                     fuzzy: Tier.cityFuzzy)
    }

    private static let wholeWordBonus = 20
    private static let aliasPenalty = 5
    private static let editPenalty = 30

    /// Total relevance of `document` for `query`, or nil when any term fails
    /// to match. Every term takes its single best match across all fields.
    static func score(query: Query,
                      document: Document) -> Int? {
        var total = 0
        for term in query.terms {
            guard let score = score(term: term, document: document) else {
                return nil
            }
            total += score
        }
        return total
    }

    /// Each stage below is strictly higher-tier than the ones after it, so
    /// the first stage that matches is the best match.
    static func score(term: Query.Term,
                      document: Document) -> Int? {
        if document.code == term.token {
            return Tier.codeExact
        }
        if hasPrefix(term.token, document.code) {
            return Tier.codePrefix + coverage(term.token.count, document.code.count)
        }
        if let score = directScore(term: term, field: document.name, tiers: .name) {
            return score
        }
        if let score = directScore(term: term, field: document.city, tiers: .city) {
            return score
        }
        guard term.maxEdits > 0 else {
            return nil
        }
        if let score = fuzzyScore(term: term, field: document.name, tiers: .name) {
            return score
        }
        return fuzzyScore(term: term, field: document.city, tiers: .city)
    }

    private static func directScore(term: Query.Term,
                                    field: Field,
                                    tiers: FieldTiers) -> Int? {
        var best: Int?
        for (index, word) in field.words.enumerated() {
            let base = index == 0 ? tiers.start : tiers.word - positionPenalty(index)
            if hasPrefix(term.token, word.primary) {
                best = max(best ?? .min, base + coverage(term.token.count, word.primary.count))
            }
            for alias in word.aliases where hasPrefix(term.token, alias) {
                best = max(best ?? .min, base + coverage(term.token.count, alias.count) - aliasPenalty)
            }
        }
        if let best {
            return best
        }
        if hasPrefix(term.token, field.joined) {
            return tiers.joined + coverage(term.token.count, field.joined.count)
        }
        if hasPrefix(term.token, field.initials) {
            return tiers.initials + coverage(term.token.count, field.initials.count)
        }
        return nil
    }

    private static func fuzzyScore(term: Query.Term,
                                   field: Field,
                                   tiers: FieldTiers) -> Int? {
        var best: Int?
        for (index, word) in field.words.enumerated() {
            guard let distance = prefixEditDistance(token: term.token, word: word.primary, limit: term.maxEdits) else {
                continue
            }
            let score = tiers.fuzzy - distance * editPenalty - positionPenalty(index)
            best = max(best ?? .min, score)
        }
        return best
    }

    private static func positionPenalty(_ index: Int) -> Int {
        min(max(index - 1, 0), 4) * 5
    }
    
    /// Whole-word matches beat any partial prefix; among partial prefixes,
    /// covering more of the word ranks higher.
    private static func coverage(_ tokenCount: Int, _ wordCount: Int) -> Int {
        guard wordCount > 0 else {
            return 0
        }
        return tokenCount == wordCount ? wholeWordBonus : (10 * tokenCount) / wordCount
    }
    
    static func hasPrefix(_ prefix: Token, _ token: Token) -> Bool {
        guard !prefix.isEmpty, prefix.count <= token.count else {
            return false
        }
        var index = 0
        while index < prefix.count {
            if prefix[index] != token[index] {
                return false
            }
            index += 1
        }
        return true
    }
    
    /// Bounded optimal string alignment distance (Levenshtein plus adjacent
    /// transpositions) between `token` and the closest prefix of `word`, or
    /// nil when every prefix is more than `limit` edits away. Only the
    /// diagonal band of width 2·limit+1 is evaluated and the rows live in a
    /// temporary stack buffer, so a call costs O(token.count · limit) with no
    /// heap allocation.
    static func prefixEditDistance(token: Token,
                                   word: Token,
                                   limit: Int) -> Int? {
        let tokenCount = token.count
        // Prefixes longer than the token plus the edit budget can only cost more.
        let wordCount = min(word.count, tokenCount + limit)
        guard tokenCount > 0, wordCount > 0, limit >= 0 else {
            return nil
        }
        // Within `limit` edits at least one of the token's first limit+1 bytes
        // must survive, and it can only land within the word's first limit+1
        // bytes. Checking that up front rejects most words with a few compares.
        guard sharesLeadingByte(token, word, within: limit) else {
            return nil
        }
        let unreachable = limit + 1
        let stride = wordCount + 1
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 3 * stride) { rows -> Int? in
            var twoBack = 0
            var previous = stride
            var current = 2 * stride
            for column in 0...wordCount {
                rows[previous + column] = min(column, unreachable)
            }
            for row in 1...tokenCount {
                let low = max(0, row - limit)
                let high = min(wordCount, row + limit)
                guard low <= high else {
                    return nil
                }
                for column in 0...wordCount {
                    rows[current + column] = unreachable
                }
                var rowMinimum = unreachable
                if low == 0 {
                    rows[current] = min(row, unreachable)
                    rowMinimum = rows[current]
                }
                var column = max(1, low)
                while column <= high {
                    let substitution = token[row - 1] == word[column - 1] ? 0 : 1
                    var value = min(rows[previous + column] + 1,
                                    rows[current + column - 1] + 1)
                    value = min(value, rows[previous + column - 1] + substitution)
                    if row > 1,
                       column > 1,
                       token[row - 1] == word[column - 2],
                       token[row - 2] == word[column - 1] {
                        value = min(value, rows[twoBack + column - 2] + 1)
                    }
                    value = min(value, unreachable)
                    rows[current + column] = value
                    rowMinimum = min(rowMinimum, value)
                    column += 1
                }
                if rowMinimum > limit {
                    return nil
                }
                (twoBack, previous, current) = (previous, current, twoBack)
            }
            // The final row holds the distance from the whole token to each word prefix.
            var best = unreachable
            for column in 0...wordCount {
                best = min(best, rows[previous + column])
            }
            return best <= limit ? best : nil
        }
    }
    
    private static func sharesLeadingByte(_ token: Token,
                                          _ word: Token,
                                          within limit: Int) -> Bool {
        let tokenEnd = min(token.count, limit + 1)
        let wordEnd = min(word.count, limit + 1)
        var tokenIndex = 0
        while tokenIndex < tokenEnd {
            var wordIndex = 0
            while wordIndex < wordEnd {
                if token[tokenIndex] == word[wordIndex] {
                    return true
                }
                wordIndex += 1
            }
            tokenIndex += 1
        }
        return false
    }
}

// MARK: - StationRow

extension Array where Element == StationRow {
    /// Rows matching every word of `query`, best match first. An empty or
    /// punctuation-only query returns the array unchanged.
    func search(query: String) -> Self {
        let query = StationSearch.Query(query)
        guard !query.isEmpty else {
            return self
        }
        var scored: [(row: StationRow, score: Int)] = []
        for row in self {
            if let score = StationSearch.score(query: query, document: row.searchDocument) {
                scored.append((row, score))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.row.title != rhs.row.title {
                return lhs.row.title < rhs.row.title
            }
            return lhs.row.station.code < rhs.row.station.code
        }
        return scored.map(\.row)
    }
}
