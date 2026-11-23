import Foundation

// Word handling of the search, ported from `_system/apps/dashboard/static/search-rank.js`.
//
// JavaScript works on UTF-16 code units and compares them one by one. Swift's `String`
// works on grapheme clusters and treats canonically equal strings as equal. Where the
// difference could change a result, this file compares scalars or bytes instead.

/// How a query word matches a word of a page (FR-002).
public enum MatchKind: String, Sendable { case exact, prefix, form, typo }

/// A word with what the matching needs, computed once.
struct WordInfo: Sendable {
    let text: String
    let scalars: [UInt32]
    let stem: String
    let stemScalars: [UInt32]
    let isID: Bool

    init(_ text: String) {
        self.text = text
        scalars = text.unicodeScalars.map(\.value)
        stem = Search.stem(text)
        stemScalars = stem.unicodeScalars.map(\.value)
        isID = Search.isID(scalars)
    }
}

/// A word match: its kind and, for a typo, its cost (JS `matchWord` result without `from` and `to`).
struct WordMatch: Sendable {
    let kind: MatchKind
    let cost: Int
}

/// The text rules of the ranker. A namespace, so the helpers do not clutter the module.
enum Search {
    // JS WORD_RE, ID_RE, SUFFIXES
    static let suffixes = ["ing", "ed", "es", "s"]

    /// The longest query the ranker looks at, and the most words of it. The JavaScript has no
    /// limit. These keep the work bounded for any input.
    static let longestQuery = 200
    static let mostQueryWords = 16

    // MARK: characters

    static func isLetter(_ u: Unicode.Scalar) -> Bool {
        if u.value < 0x80 { return (0x41...0x5A).contains(u.value) || (0x61...0x7A).contains(u.value) }
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    static func isNumber(_ u: Unicode.Scalar) -> Bool {
        if u.value < 0x80 { return (0x30...0x39).contains(u.value) }
        switch u.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    static func isAsciiDigit(_ u: Unicode.Scalar) -> Bool { (0x30...0x39).contains(u.value) }

    /// JS `\s` and `trim()`: white space and line terminators.
    static func isJSSpace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    // MARK: normalising and case

    /// JS `norm`: NFC.
    static func norm(_ s: String) -> String {
        s.utf8.allSatisfy { $0 < 0x80 } ? s : s.precomposedStringWithCanonicalMapping
    }

    /// JS `toLowerCase`: the full Unicode mapping, with the final sigma rule.
    static func lowercased(_ s: String) -> String {
        if s.utf8.allSatisfy({ $0 < 0x80 }) { return s.lowercased() }
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        for (i, u) in scalars.enumerated() {
            if u == "\u{03A3}" {
                out.append(isFinalSigma(scalars, i) ? "\u{03C2}" : "\u{03C3}")
            } else {
                out.append(contentsOf: u.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return String(out)
    }

    private static func isFinalSigma(_ s: [Unicode.Scalar], _ i: Int) -> Bool {
        var before = i - 1
        while before >= 0, s[before].properties.isCaseIgnorable { before -= 1 }
        guard before >= 0, s[before].properties.isCased else { return false }
        var after = i + 1
        while after < s.count, s[after].properties.isCaseIgnorable { after += 1 }
        return !(after < s.count && s[after].properties.isCased)
    }

    /// Go `strings.ToLower`: one scalar maps to one scalar, and `Σ` is always `σ`.
    /// The only scalar whose full mapping is longer is `İ`, which Go maps to `i`.
    static func goLowercased(_ s: String) -> String {
        if s.utf8.allSatisfy({ $0 < 0x80 }) { return s.lowercased() }
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let mapped = u.properties.lowercaseMapping.unicodeScalars
            out.append(mapped.first ?? u)
        }
        return String(out)
    }

    /// Byte-wise equality: JavaScript's `===`. Swift's `==` also equates canonical equivalents.
    static func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

    /// Whether `needle` occurs in `hay`: JS `indexOf(...) !== -1`, on bytes.
    static func contains(_ hay: String, _ needle: String) -> Bool {
        let h = Array(hay.utf8), n = Array(needle.utf8)
        if n.isEmpty { return true }
        if n.count > h.count { return false }
        for start in 0...(h.count - n.count) where h[start] == n[0] && h[start...].starts(with: n) { return true }
        return false
    }

    // MARK: words

    /// A word of a text and where it stands, in UTF-16 offsets.
    struct Span {
        let text: String
        let from: Int
        let to: Int
    }

    /// JS `WORD_RE = /\p{L}+-\d+|[\p{L}\p{N}]+/gu`: an ID such as `STK-023`, or a run of letters and numbers.
    /// `text` is expected in NFC.
    static func spans(_ text: String) -> [Span] {
        let bytes = Array(text.utf8)
        if bytes.allSatisfy({ $0 < 0x80 }) { return asciiSpans(bytes) }
        let s = Array(text.unicodeScalars)
        let n = s.count
        var offsets = [Int](repeating: 0, count: n + 1)
        for i in 0..<n { offsets[i + 1] = offsets[i] + s[i].utf16.count }
        func span(_ a: Int, _ b: Int) -> Span {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: s[a..<b])
            return Span(text: String(view), from: offsets[a], to: offsets[b])
        }
        var out: [Span] = []
        var i = 0
        while i < n {
            if isLetter(s[i]) {
                var j = i
                while j < n, isLetter(s[j]) { j += 1 }
                if j < n, s[j] == "-" {
                    var k = j + 1
                    while k < n, isAsciiDigit(s[k]) { k += 1 }
                    if k > j + 1 { out.append(span(i, k)); i = k; continue }
                }
                var k = j
                while k < n, isLetter(s[k]) || isNumber(s[k]) { k += 1 }
                out.append(span(i, k)); i = k
            } else if isNumber(s[i]) {
                var k = i
                while k < n, isLetter(s[k]) || isNumber(s[k]) { k += 1 }
                out.append(span(i, k)); i = k
            } else {
                i += 1
            }
        }
        return out
    }

    /// `spans` for a text of ASCII only, where a byte is a code point and a UTF-16 unit.
    private static func asciiSpans(_ b: [UInt8]) -> [Span] {
        func isLetter(_ c: UInt8) -> Bool { (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A }
        func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
        var out: [Span] = []
        let n = b.count
        var i = 0
        while i < n {
            guard isLetter(b[i]) || isDigit(b[i]) else { i += 1; continue }
            var end = i
            if isLetter(b[i]) {
                var j = i
                while j < n, isLetter(b[j]) { j += 1 }
                if j + 1 < n, b[j] == 0x2D, isDigit(b[j + 1]) {
                    end = j + 1
                    while end < n, isDigit(b[end]) { end += 1 }
                }
            }
            if end == i {
                end = i
                while end < n, isLetter(b[end]) || isDigit(b[end]) { end += 1 }
            }
            out.append(Span(text: String(decoding: b[i..<end], as: UTF8.self), from: i, to: end))
            i = end
        }
        return out
    }

    /// JS `words`.
    static func words(_ s: String) -> [String] { spans(norm(s)).map(\.text) }

    /// JS `len`: the number of code points.
    static func len(_ w: String) -> Int { w.unicodeScalars.count }

    /// JS `ID_RE = /^\p{L}+-\d+$/u`.
    static func isID(_ w: [UInt32]) -> Bool {
        var i = 0
        while i < w.count, let u = Unicode.Scalar(w[i]), isLetter(u) { i += 1 }
        guard i > 0, i < w.count, w[i] == 0x2D else { return false }
        let digits = w[(i + 1)...]
        return !digits.isEmpty && digits.allSatisfy { (0x30...0x39).contains($0) }
    }

    // MARK: matching

    /// JS `stem`: common English endings count as the same word (FR-002).
    static func stem(_ w: String) -> String {
        let n = w.utf16.count
        for s in suffixes {
            if n > s.utf16.count, w.utf16.suffix(s.utf16.count).elementsEqual(s.utf16), len(w) - s.utf16.count >= 3 {
                return String(String.UnicodeScalarView(w.unicodeScalars.dropLast(s.utf16.count)))
            }
        }
        return w
    }

    /// JS `tolerance`: 8 letters or more allow two edits, 4 or more one.
    static func tolerance(_ n: Int) -> Int { n >= 8 ? 2 : n >= 4 ? 1 : 0 }

    /// JS `distance`: Damerau-Levenshtein distance (optimal string alignment), or more than `max`
    /// once it is clear the distance exceeds `max`. Only the cells within `max` of the diagonal can
    /// hold a value of `max` or less, so only those are computed: `|a| * (2 * max + 1)` steps at most.
    /// A result of `max` or less is exact, which is all `matchWord` uses.
    static func distance(_ a: [UInt32], _ b: [UInt32], _ max: Int) -> Int {
        if abs(a.count - b.count) > max { return max + 1 }
        let n = a.count, m = b.count
        if n == 0 { return m }
        if m == 0 { return n }
        let over = max + 1
        // One edit (a substitution, an insertion, a deletion or a swap of neighbours) cannot change
        // both ends of words of 3 letters or more.
        if max == 1, n >= 3, m >= 3, a[0] != b[0], a[n - 1] != b[m - 1] { return over }
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 3 * (m + 1)) { buffer in
            buffer.initialize(repeating: over)
            var prev2 = buffer.baseAddress!, prev = prev2 + (m + 1), cur = prev + (m + 1)
            for j in 0...Swift.min(m, max) { prev[j] = j }
            for i in 1...n {
                let lo = Swift.max(1, i - max), hi = Swift.min(m, i + max)
                if i <= max { cur[0] = i } else { cur[lo - 1] = over }
                var low = i <= max ? i : over
                for j in lo...hi {
                    let c = a[i - 1] == b[j - 1] ? 0 : 1
                    var d = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c)
                    if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                        d = Swift.min(d, prev2[j - 2] + 1)
                    }
                    cur[j] = d
                    if d < low { low = d }
                }
                if low > max { return over }
                if hi < m { cur[hi + 1] = over }
                (prev2, prev, cur) = (prev, cur, prev2)
            }
            return prev[m]
        }
    }

    static func isPrefix(_ q: [UInt32], of w: [UInt32]) -> Bool {
        if q.count > w.count { return false }
        for i in 0..<q.count where q[i] != w[i] { return false }
        return true
    }

    /// JS `matchWord`: how the query word `q` matches the text word `w` (both lower-case), or nil.
    /// Words of 3 letters or fewer and IDs match only exactly or as a prefix. 4 to 7 letters allow
    /// one wrong, missing, extra or swapped letter, 8 or more two.
    static func matchWord(_ q: WordInfo, _ w: WordInfo) -> WordMatch? {
        if q.scalars == w.scalars { return WordMatch(kind: .exact, cost: 0) }
        let n = q.scalars.count
        let strict = n <= 3 || q.isID
        if isPrefix(q.scalars, of: w.scalars) { return WordMatch(kind: .prefix, cost: 0) }
        if !strict, q.stemScalars == w.stemScalars { return WordMatch(kind: .form, cost: 0) }
        if strict || w.isID { return nil }
        let tol = tolerance(n)
        var d: Int? = distance(q.scalars, w.scalars, tol)
        if d! > tol {
            // without an ending to strip on either side the stems are the words: nothing new to try
            if q.stemScalars.count == n, w.stemScalars.count == w.scalars.count { return nil }
            let tolStem = tolerance(q.stemScalars.count)
            let sd = distance(q.stemScalars, w.stemScalars, tolStem)
            d = sd <= tolStem ? sd : nil
        }
        guard let d else { return nil }
        // a typo rarely hits the first letter: a match that changes it ranks lower
        return WordMatch(kind: .typo, cost: d + (q.scalars[0] == w.scalars[0] ? 0 : 1))
    }
}

/// How the query word `query` matches the page word `word` (both lower-case), or nil.
/// Ports JS `matchWord`, which `search-rank.js` exports as `S42Search.matchWord`.
public func matchKind(query: String, word: String) -> MatchKind? {
    Search.matchWord(WordInfo(query), WordInfo(word))?.kind
}

/// Common English endings count as the same word (FR-002). Ports JS `stem`.
public func stem(_ word: String) -> String {
    Search.stem(word)
}
