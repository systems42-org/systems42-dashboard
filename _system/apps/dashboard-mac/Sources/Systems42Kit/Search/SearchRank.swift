import Foundation

// The ranker of the search, ported from `_system/apps/dashboard/static/search-rank.js`.
//
// Relevance is a 0 to 100 percentage, decided by how and where each query word matched. How
// comes first, in tiers: a word as typed (exact or prefix, 40 to 100), another name of a glossary
// term (33 to 39, FR-003), a word form (27 to 32), a typo (21 to 26, FR-002). A page's tier is the
// tier of its weakest word. Within a tier, places rank strongest first: id, title, alias, field,
// type, body. Pages with every query word come first, then pages with only some, at most 20
// (FR-004).
//
// The JavaScript scans the words of every page for every query word. This port builds a
// vocabulary of all words once, matches each query word against the vocabulary, and ranks only
// the pages that hold a matching word. A page without one has no match in the JavaScript either,
// so the result is the same.

// MARK: public types

/// The facets of a search (FR-009). An empty set leaves that filter off. Within a set, any value
/// passes. Values are compared in lower case.
public struct SearchFilter: Sendable, Equatable {
    public var types: Set<String>
    public var statuses: Set<String>
    public var priorities: Set<String>
    public var tags: Set<String>

    public init(types: Set<String> = [], statuses: Set<String> = [], priorities: Set<String> = [], tags: Set<String> = []) {
        self.types = types
        self.statuses = statuses
        self.priorities = priorities
        self.tags = tags
    }
}

/// The sentence where a query matched, as text and the parts to mark (FR-007). The text is plain:
/// a `<` in it is a `<`. Long sentences are cut at word gaps and carry an ellipsis at a cut end.
public struct Passage: Sendable, Equatable {
    public let text: String
    /// The words to mark, as UTF-16 offsets into `text`, in order.
    public let marks: [Range<Int>]

    public var marked: [String] {
        let units = Array(text.utf16)
        return marks.map { String(decoding: units[$0], as: UTF16.self) }
    }

    /// The text with the marked words in strong emphasis.
    public var attributed: AttributedString {
        var result = AttributedString(text)
        for mark in marks {
            let from = String.Index(utf16Offset: mark.lowerBound, in: text)
            let to = String.Index(utf16Offset: mark.upperBound, in: text)
            if let range = Range(from..<to, in: result) { result[range].inlinePresentationIntent = .stronglyEmphasized }
        }
        return result
    }
}

/// One result of a search: a page that matches, or a page one link away from a strong match.
public struct SearchHit: Identifiable, Sendable {
    public enum Group: Sendable { case hit, related }

    public let id: String
    /// Where the page lives. Nil for an entry that came from JSON.
    public let ref: PageRef?
    public let title, type, status: String
    /// Why this page is a hit when it does not contain the words as typed (FR-005). Nil for an exact hit.
    public let note: String?
    public let group: Group
    /// The relevance, 0 to 100 (`Math.round(raw)`). 0 for a related page.
    public let score: Int
    private let source: PassageSource?

    /// What the passage is cut from: the page text and the words that matched in it.
    fileprivate struct PassageSource: Sendable {
        let plain: String
        let marks: Set<String>
    }

    fileprivate init(
        id: String, ref: PageRef?, title: String, type: String, status: String, note: String?, group: Group, score: Int,
        source: PassageSource?
    ) {
        self.id = id
        self.ref = ref
        self.title = title
        self.type = type
        self.status = status
        self.note = note
        self.group = group
        self.score = score
        self.source = source
    }

    /// The sentence where the query matched (FR-007). Nil unless the search was asked for passages,
    /// for related pages, and for a page without text. It is cut from the page text on each read, so
    /// a long result list costs nothing until a row asks for its passage.
    public var passage: Passage? {
        source.flatMap { Passage(in: $0.plain, marks: $0.marks) }
    }
}

// MARK: prepared index

private enum Place: Int, CaseIterable {
    // JS PLACES, in the order of PLACE
    case id, title, alias, field, type, body

    /// JS PLACE: the base score of the place on the exact tier's scale.
    var base: Int { [90, 80, 70, 60, 50, 40][rawValue] }
}

/// The words of one place of one page, in the order the JavaScript's `Map` holds them.
private struct PlaceWords: Sendable {
    var ids: [Int32] = []
    var origs: [String] = []
    /// How often each word occurs. Only the body keeps it.
    var counts: [Int32] = []
}

private struct PreparedEntry: Sendable {
    var places: [PlaceWords]
    var titleLc: String
    var aliasLc: [String]
}

/// JS `prep`, for the whole index. Immutable once built.
final class PreparedIndex: Sendable {
    fileprivate let vocab: [WordInfo]
    /// What a vocabulary word must have to match a query word at all, kept in flat arrays so the
    /// scan of the vocabulary skips most words without touching them.
    fileprivate let firsts: [UInt32]
    fileprivate let lengths: [Int32]
    fileprivate let stemLengths: [Int32]
    fileprivate let stemHashes: [Int]
    fileprivate let records: [PreparedEntry]
    /// Per word, the entries that hold it in any place.
    fileprivate let postings: [[Int32]]
    /// JS `titles`: a title as words, lower-case, to the title as written. The last page wins.
    fileprivate let titles: [String: String]
    /// JS `groups` of `units`: per term, the words of each name, lower-case.
    fileprivate let groups: [[[String]]]
    fileprivate let byId: [String: Int]
    /// The position of each title in the order of JS `localeCompare(_, "en")`. Equal titles share one.
    fileprivate let titleRank: [Int32]

    init(entries: [SearchEntry], synonyms: [[String]]) {
        var vocabIds: [String: Int32] = [:]
        var vocab: [WordInfo] = []
        func intern(_ lc: String) -> Int32 {
            if let id = vocabIds[lc] { return id }
            let id = Int32(vocab.count)
            vocabIds[lc] = id
            vocab.append(WordInfo(lc))
            return id
        }
        // JS `wordMap`: an ID such as STK-023 is one word, and its parts are words too
        func wordMap(_ s: String, counting: Bool = false) -> PlaceWords {
            var place = PlaceWords()
            var position: [Int32: Int] = [:]
            func add(_ w: String) {
                let id = intern(Search.lowercased(w))
                if let at = position[id] {
                    if counting { place.counts[at] += 1 }
                } else {
                    position[id] = place.ids.count
                    place.ids.append(id)
                    place.origs.append(w)
                    if counting { place.counts.append(1) }
                }
            }
            for w in Search.words(s) {
                add(w)
                if Search.isID(w.unicodeScalars.map(\.value)) {
                    for part in w.split(separator: "-", omittingEmptySubsequences: false) { add(String(part)) }
                }
            }
            return place
        }

        var records: [PreparedEntry] = []
        var titles: [String: String] = [:]
        var byId: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            let field = entry.fields.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                .map { (entry.fields[$0] ?? []).joined(separator: " ") }.joined(separator: " ")
            let places = [
                wordMap(entry.id), wordMap(entry.title), wordMap(entry.aliases.joined(separator: " ")),
                wordMap(field), wordMap(entry.type), wordMap(entry.plain, counting: true),
            ]
            let titleLc = Search.lowercased(Search.words(entry.title).joined(separator: " "))
            records.append(PreparedEntry(
                places: places, titleLc: titleLc,
                aliasLc: entry.aliases.map { Search.lowercased(Search.words($0).joined(separator: " ")) }
            ))
            titles[titleLc] = entry.title
            byId[entry.id] = index
        }
        var postings = [[Int32]](repeating: [], count: vocab.count)
        for (index, record) in records.enumerated() {
            for place in record.places {
                for id in place.ids where postings[Int(id)].last != Int32(index) { postings[Int(id)].append(Int32(index)) }
            }
        }
        self.vocab = vocab
        self.firsts = vocab.map { $0.scalars.first ?? 0 }
        self.lengths = vocab.map { Int32($0.scalars.count) }
        self.stemLengths = vocab.map { Int32($0.stemScalars.count) }
        self.stemHashes = vocab.map { Self.hash($0.stemScalars) }
        self.records = records
        self.postings = postings
        self.titles = titles
        self.byId = byId
        self.groups = synonyms.map { group in
            group.map { name in Search.words(name).map(Search.lowercased) }.filter { !$0.isEmpty }
        }
        self.titleRank = Self.rankTitles(entries.map(\.title))
    }

    fileprivate static func hash(_ scalars: [UInt32]) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for u in scalars { h = (h ^ UInt64(u)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h)
    }

    /// JS `localeCompare(_, "en")` on titles, once per index so that a tie costs an integer compare.
    private static func rankTitles(_ titles: [String]) -> [Int32] {
        let english = Locale(identifier: "en")
        func compare(_ a: String, _ b: String) -> ComparisonResult { a.compare(b, options: [], range: nil, locale: english) }
        let order = titles.indices.sorted { compare(titles[$0], titles[$1]) == .orderedAscending }
        var ranks = [Int32](repeating: 0, count: titles.count)
        var rank: Int32 = 0
        for (i, index) in order.enumerated() {
            if i > 0, compare(titles[order[i - 1]], titles[index]) != .orderedSame { rank += 1 }
            ranks[index] = rank
        }
        return ranks
    }
}

// MARK: ranking

/// JS TIER: exact and prefix 0, synonym 1, form 2, typo 3. A synonym is no kind of word match.
private func tierOf(_ kind: MatchKind) -> Int {
    switch kind {
    case .exact, .prefix: 0
    case .form: 2
    case .typo: 3
    }
}

/// JS BAND: the score band of each tier below the exact one.
private let bands: [(floor: Int, width: Int)] = [(0, 0), (33, 6), (27, 5), (21, 5)]

private let synonymTier = 1

/// JS `weight`: order of two word matches: tier, then (typos only) the size of the typo, then exact before prefix.
private func matchWeight(_ kind: MatchKind, _ cost: Int) -> Double {
    Double(tierOf(kind) * 10 + cost) + (kind == .prefix ? 0.5 : 0)
}

/// The best match of one query word among the words of one place (JS `bestIn` result).
private struct WordHit {
    let kind: MatchKind
    let cost: Int
    let from: String
    let to: String
    let word: Int32
    let position: Int
}

/// A query unit: a single word, or a glossary term's name or alias that the query contains,
/// with its alternatives (JS `units`).
private struct QueryUnit {
    let words: [String]
    let via: String?
    /// The words as typed first, then the other names of the same term.
    let alts: [[String]]
    /// Per word of each alternative, how it matches every word of the vocabulary.
    var tables: [[[UInt8]]] = []
}

/// The best place and match for one query unit in one page (JS `matchUnit` result).
private struct UnitMatch {
    let place: Place
    let tier: Int
    let key: Int
    let fit: Double
    let match: WordHit
    /// The vocabulary ids of the matched words, one per word of the alternative.
    let words: [Int32]
    let via: String?
    let score: Double
}

private struct Ranked {
    let index: Int
    let matches: [UnitMatch]
    let freq: Int
    let full: Bool
    let raw: Double
    let score: Int
    let note: String?
}

extension PreparedIndex {
    /// JS `bestIn`.
    private func bestIn(_ place: PlaceWords, _ q: String, _ table: [UInt8]) -> WordHit? {
        var best: (code: UInt8, position: Int)?
        var bestWeight = 0.0
        for position in place.ids.indices {
            let code = table[Int(place.ids[position])]
            if code == 0 { continue }
            let w = weight(code)
            if best == nil || w < bestWeight { best = (code, position); bestWeight = w }
        }
        guard let best else { return nil }
        let m = Self.decode(best.code)
        return WordHit(kind: m.kind, cost: m.cost, from: q, to: place.origs[best.position], word: place.ids[best.position], position: best.position)
    }

    private static let kinds: [MatchKind] = [.exact, .prefix, .form, .typo]

    /// A match as one byte for the table of the vocabulary: 0 is no match.
    private static func encode(_ m: WordMatch?) -> UInt8 {
        guard let m else { return 0 }
        return UInt8(1 + kinds.firstIndex(of: m.kind)! * 4 + m.cost)
    }

    fileprivate static func decode(_ code: UInt8) -> WordMatch {
        let c = Int(code) - 1
        return WordMatch(kind: kinds[c / 4], cost: c % 4)
    }

    /// JS `weight` on an encoded match.
    private func weight(_ code: UInt8) -> Double {
        let m = Self.decode(code)
        return matchWeight(m.kind, m.cost)
    }

    /// How the query word `q` matches every word of the vocabulary. A word is skipped when it can
    /// neither start with `q`, nor share its stem, nor be within the typo distance of `q` or its stem.
    private func table(for q: WordInfo) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: vocab.count)
        let n = q.scalars.count
        let strict = n <= 3 || q.isID
        let first = q.scalars[0]
        let stemHash = Self.hash(q.stemScalars)
        let tol = Search.tolerance(n), tolStem = Search.tolerance(q.stemScalars.count)
        let firsts = self.firsts, lengths = self.lengths, stemLengths = self.stemLengths, stemHashes = self.stemHashes
        let stemLength = q.stemScalars.count
        for i in 0..<firsts.count {
            let length = Int(lengths[i])
            var possible = firsts[i] == first && length >= n
            if !strict, !possible {
                possible = stemHashes[i] == stemHash || abs(length - n) <= tol || abs(Int(stemLengths[i]) - stemLength) <= tolStem
            }
            if possible { table[i] = Self.encode(Search.matchWord(q, vocab[i])) }
        }
        return table
    }

    /// JS `units`.
    private func units(_ qwords: [String]) -> [QueryUnit] {
        var out: [QueryUnit] = []
        var i = 0
        while i < qwords.count {
            var found: (group: Int, name: Int)?
            var length = 0
            for (g, group) in groups.enumerated() {
                for (n, ws) in group.enumerated() where found == nil || ws.count > length {
                    let fits = ws.indices.allSatisfy { k in
                        i + k < qwords.count && (Search.same(qwords[i + k], ws[k]) || Search.same(Search.stem(qwords[i + k]), Search.stem(ws[k])))
                    }
                    if fits { found = (g, n); length = ws.count }
                }
            }
            if let found {
                let group = groups[found.group]
                let typed = Array(qwords[i..<(i + length)])
                let name = group[0].joined(separator: " ")
                let via = titles[name].flatMap { $0.isEmpty ? nil : $0 } ?? name
                let others = group.indices.filter { $0 != found.name }.map { group[$0] }
                out.append(QueryUnit(words: typed, via: via, alts: [typed] + others))
                i += length
            } else {
                out.append(QueryUnit(words: [qwords[i]], via: nil, alts: [[qwords[i]]]))
                i += 1
            }
        }
        return out
    }

    /// JS `matchUnit`: every word of an alternative must match within the same place.
    private func matchUnit(_ record: PreparedEntry, _ unit: QueryUnit) -> UnitMatch? {
        var best: UnitMatch?
        for place in Place.allCases {
            alternatives: for (ai, alt) in unit.alts.enumerated() {
                var worst: WordHit?
                var matched: [Int32] = []
                for (k, q) in alt.enumerated() {
                    guard let m = bestIn(record.places[place.rawValue], q, unit.tables[ai][k]) else { continue alternatives }
                    matched.append(m.word)
                    if worst == nil || matchWeight(m.kind, m.cost) > matchWeight(worst!.kind, worst!.cost) { worst = m }
                }
                guard let worst else { continue }
                let tier = Swift.max(tierOf(worst.kind), ai > 0 ? synonymTier : 0)
                let key = tier * 1000 + (100 - place.base) + worst.cost   // lower is better
                if let best, key >= best.key { continue }
                let fit = Swift.max(0, Swift.min(1, Double(place.base - 40) / 50 - 0.1 * Double(worst.cost)))
                let score = tier == 0
                    ? Double(place.base - (worst.kind == .prefix ? 2 : 0))
                    : Double(bands[tier].floor) + Double(bands[tier].width) * fit
                best = UnitMatch(place: place, tier: tier, key: key, fit: fit, match: worst, words: matched,
                                 via: ai > 0 ? unit.via : nil, score: score)
            }
        }
        return best
    }

    /// JS `relevance`: a page's score. Its weakest word's tier decides the band (FR-002).
    private func relevance(_ record: PreparedEntry, _ phrases: [String], _ matches: [UnitMatch]) -> Double {
        let weakest = matches.map(\.tier).max() ?? 0
        if weakest > 0 {
            let fit = matches.reduce(0) { $0 + $1.fit } / Double(matches.count)
            return Double(bands[weakest].floor) + Double(bands[weakest].width) * fit
        }
        func all(_ place: Place) -> Bool {
            matches.allSatisfy { $0.place == place && $0.via == nil && ($0.match.kind == .exact || $0.match.kind == .prefix) }
        }
        func each(_ test: (String) -> Bool) -> Bool { phrases.contains(where: test) }
        if all(.title) {
            if each({ Search.same(record.titleLc, $0) }) { return 100 }                          // exact title
            if each({ record.titleLc.utf8.starts(with: $0.utf8) }) { return 92 }                // title prefix
            if each({ Search.contains(record.titleLc, $0) }) { return 85 }                       // phrase in title
        }
        // an alias, exactly: below every title phrase and every page with all words in its title (FR-003)
        if all(.alias), each({ phrase in record.aliasLc.contains { Search.same($0, phrase) } }) { return 78 }
        let sum = matches.reduce(0) { $0 + $1.score }
        return sum / Double(matches.count)
    }

    /// JS `reason`: why a page with every query word is a hit when it does not contain the words as
    /// typed. The first non-exact word decides (FR-005). An exact or prefix hit has no note.
    private func reason(_ entry: SearchEntry, _ matches: [UnitMatch]) -> String? {
        for m in matches {
            if let via = m.via { return "via alias of " + via }
            if m.place == .alias { return "via alias of " + entry.title }
            if m.match.kind == .typo { return "typo: \(m.match.from) → \(m.match.to)" }
            if m.match.kind == .form { return "word form: \(m.match.from) → \(m.match.to)" }
        }
        return nil
    }

    /// JS `rank`: pages with every word, then relevance, then the number of matched words, then how
    /// often the words occur in the body, then title.
    fileprivate func rank(_ query: String, entries: [SearchEntry]) -> [Ranked] {
        let capped = String(String.UnicodeScalarView(query.unicodeScalars.prefix(Search.longestQuery)))
        let qwords = Array(Search.words(capped).map(Search.lowercased).prefix(Search.mostQueryWords))
        guard !qwords.isEmpty else { return [] }
        // glossary terms are found in the query as typed, filler words included ("definition of done"),
        // then single filler words drop out
        var qunits = units(qwords)
        let content = qunits.filter { $0.via != nil || !Search.stopWords.contains($0.words[0]) }
        if !content.isEmpty { qunits = content }
        // a title or alias may contain the filler words too ("search the wiki")
        var phrases = [qwords.joined(separator: " ")]
        let short = qunits.flatMap(\.words).joined(separator: " ")
        if short != phrases[0] { phrases.append(short) }

        // match every word of the queries against the vocabulary once (JS `memo`)
        var tables: [String: [UInt8]] = [:]
        var candidates = Set<Int32>()
        for u in qunits.indices {
            qunits[u].tables = qunits[u].alts.map { alt in
                alt.map { q in
                    if let table = tables[q] { return table }
                    let table = table(for: WordInfo(q))
                    tables[q] = table
                    for (id, code) in table.enumerated() where code != 0 { candidates.formUnion(postings[id]) }
                    return table
                }
            }
        }

        var out: [Ranked] = []
        for index in candidates.sorted() {
            let record = records[Int(index)]
            let matches = qunits.compactMap { matchUnit(record, $0) }
            if matches.isEmpty { continue }
            let n = qunits.count
            let full = matches.count == n
            let freq = matches.reduce(0) { sum, m in
                sum + (m.place == .body ? Int(record.places[Place.body.rawValue].counts[m.match.position]) : 0)
            }
            let sum = matches.reduce(0) { $0 + $1.score }
            let raw = full ? relevance(record, phrases, matches) : Swift.min(20, sum / Double(n) / 4)
            out.append(Ranked(
                index: Int(index), matches: matches, freq: freq, full: full, raw: raw,
                score: Int(raw.rounded(.toNearestOrAwayFromZero)),
                note: full ? reason(entries[Int(index)], matches) : "matches \(matches.count) of \(n) words"
            ))
        }
        // stable: the final tie breaks by the position in the index, as JS `sort` is stable
        return out.sorted { a, b in
            if a.full != b.full { return a.full }
            if a.raw != b.raw { return a.raw > b.raw }
            if a.matches.count != b.matches.count { return a.matches.count > b.matches.count }
            if a.freq != b.freq { return a.freq > b.freq }
            let ta = titleRank[a.index], tb = titleRank[b.index]
            if ta != tb { return ta < tb }
            return a.index < b.index
        }
    }

    /// The words of the body in which the query matched, lower-case (JS `passage`: `marks`).
    fileprivate func passageMarks(_ matches: [UnitMatch]) -> Set<String> {
        var marks = Set<String>()
        for m in matches where m.place == .body {
            for id in m.words { marks.insert(vocab[Int(id)].text) }
        }
        return marks
    }
}

extension Passage {
    /// JS `passage`: the first sentence of `plain` that holds a marked word, else its first
    /// sentence, with the marked words found in it. A long sentence keeps PASSAGE_MAX characters
    /// around the first mark, cut at word gaps. Nil when there is no text.
    fileprivate init?(in plain: String, marks: Set<String>) {
        var first: String?
        var found: String?
        Self.eachSentence(plain) { sentence in
            if first == nil { first = sentence }
            if marks.isEmpty { return true }
            if Search.spans(sentence).contains(where: { marks.contains(Search.lowercased($0.text)) }) {
                found = sentence
                return true
            }
            return false
        }
        guard let s = found ?? first else { return nil }
        let units = Array(s.utf16)
        let hits = Search.spans(s).filter { marks.contains(Search.lowercased($0.text)) }
        var start = 0, end = units.count
        if units.count > Search.passageMax {
            if let first = hits.first, first.from > Search.passageMax / 2 {
                start = Self.lastIndexOfSpace(units, first.from - 40) + 1
            }
            if start + Search.passageMax < units.count {
                let gap = Self.lastIndexOfSpace(units, start + Search.passageMax)
                end = gap > start ? gap : start + Search.passageMax
            }
        }
        var text: [UInt16] = start > 0 ? [0x2026] : []
        var ranges: [Range<Int>] = []
        var last = start
        for h in hits where h.from >= start && h.to <= end {
            text += units[last..<h.from]
            let from = text.count
            text += units[h.from..<h.to]
            ranges.append(from..<text.count)
            last = h.to
        }
        text += units[last..<end]
        if end < units.count { text.append(0x2026) }
        self.init(text: String(decoding: text, as: UTF16.self), marks: ranges)
    }

    /// JS `s.lastIndexOf(" ", from)`: -1 when there is none.
    fileprivate static func lastIndexOfSpace(_ units: [UInt16], _ from: Int) -> Int {
        var i = Swift.min(Swift.max(from, 0), units.count - 1)
        while i >= 0 {
            if units[i] == 0x20 { return i }
            i -= 1
        }
        return -1
    }

    /// JS `sentences`: the lines of the text, cut after `.`, `!` or `?` followed by white space.
    /// Calls `body` with each sentence in turn until it returns true.
    fileprivate static func eachSentence(_ plain: String, _ body: (String) -> Bool) {
        let text = Array(Search.norm(plain).utf16)
        for line in text.split(separator: 0x0A, omittingEmptySubsequences: false) {
            var start = line.startIndex
            var i = start
            func emit(_ end: Int) -> Bool {
                let piece = line[start..<end]
                guard piece.contains(where: { !Search.isJSSpace($0) }) else { return false }
                return body(String(decoding: piece, as: UTF16.self))
            }
            while i < line.endIndex {
                if i > line.startIndex, Search.isJSSpace(line[i]), [0x2E, 0x21, 0x3F].contains(line[i - 1]) {
                    if emit(i) { return }
                    var j = i
                    while j < line.endIndex, Search.isJSSpace(line[j]) { j += 1 }
                    start = j
                    i = j
                } else {
                    i += 1
                }
            }
            if emit(line.endIndex) { return }
        }
    }
}

extension Search {
    /// JS STOP_WORDS: filler words of a question don't count, unless the query has nothing else (FR-004).
    static let stopWords: Set<String> = [
        "who", "what", "when", "where", "why", "how", "the", "a", "an", "is", "are", "does", "do", "of", "to", "in", "on",
        "for", "and", "or", "with",
    ]
    /// JS PASSAGE_MAX.
    static let passageMax = 240
}

// MARK: public search

/// Ranks the pages of `index` against `query`: first the pages that hold every word, then pages
/// that hold some, then (with `withRelated`) pages one link away from the strong hits (FR-008).
/// `withPassages` adds the sentence where the query matched to each hit (FR-007). The filter
/// narrows both groups (FR-009). Ports `rank`, `filter`, `related` and `passage` of
/// `search-rank.js`, in the order `search.html` calls them.
public func search(
    _ query: String, in index: SearchIndex, filter: SearchFilter = SearchFilter(), withPassages: Bool = false,
    withRelated: Bool = true
) -> [SearchHit] {
    let entries = index.entries
    let ranked = index.prepared.rank(query, entries: entries).filter { passes(entries[$0.index], filter) }
    var out = ranked.map { r -> SearchHit in
        let entry = entries[r.index]
        return SearchHit(
            id: entry.id, ref: entry.ref, title: entry.title, type: entry.type, status: entry.status, note: r.note,
            group: .hit, score: r.score,
            source: withPassages ? .init(plain: entry.plain, marks: index.prepared.passageMarks(r.matches)) : nil
        )
    }
    if withRelated {
        for entry in related(ranked, index).filter({ passes($0.entry, filter) }) {
            out.append(SearchHit(
                id: entry.entry.id, ref: entry.entry.ref, title: entry.entry.title, type: entry.entry.type,
                status: entry.entry.status, note: entry.note, group: .related, score: 0, source: nil
            ))
        }
    }
    return out
}

/// JS `filter`: narrow to a status, a priority and a tag. An empty set leaves that filter off.
private func passes(_ entry: SearchEntry, _ f: SearchFilter) -> Bool {
    func lowered(_ set: Set<String>) -> Set<String> { Set(set.map(Search.lowercased)) }
    func holds(_ wanted: Set<String>, _ values: [String]) -> Bool {
        wanted.isEmpty || lowered(wanted).contains { w in values.contains { Search.same($0, w) } }
    }
    return holds(f.statuses, [Search.lowercased(entry.status)])
        && holds(f.priorities, entry.fields[SearchFields.priority] ?? [])
        && holds(f.tags, entry.fields[SearchFields.tags] ?? [])
        && holds(f.types, [Search.lowercased(entry.type)])
}

/// JS `related`: pages one link step away from the strong hits, for the "Related pages" group
/// (FR-008). Strong means every query word matched in the title or an alias. At most 5, never a
/// page that is a hit already, each with its reason.
private func related(_ hits: [Ranked], _ index: SearchIndex, max: Int = 5) -> [(entry: SearchEntry, note: String)] {
    let entries = index.entries
    var seen = Set(hits.map { entries[$0.index].id })
    var out: [(entry: SearchEntry, note: String)] = []
    for h in hits {
        let strong = h.full && h.matches.allSatisfy { $0.place == .title || $0.place == .alias }
        guard strong else { continue }
        for id in entries[h.index].links {
            guard let at = index.prepared.byId[id], !seen.contains(id), out.count < max else { continue }
            seen.insert(id)
            out.append((entries[at], "linked from " + entries[h.index].id))
        }
    }
    return out
}
