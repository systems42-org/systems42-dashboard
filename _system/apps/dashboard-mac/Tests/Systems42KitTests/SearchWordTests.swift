import Foundation
import Testing
import Systems42Kit

/// `matchKind` and `stem` against a literal port of the JavaScript with a full distance table.
@Suite struct SearchWordTests {
    // MARK: reference, written from search-rank.js without any shortcut

    private func scalars(_ s: String) -> [Unicode.Scalar] { Array(s.unicodeScalars) }

    private func referenceStem(_ w: String) -> String {
        for s in ["ing", "ed", "es", "s"] where w.utf16.count > s.utf16.count && w.hasSuffix(s) && scalars(w).count - s.utf16.count >= 3 {
            return String(String.UnicodeScalarView(scalars(w).dropLast(s.utf16.count)))
        }
        return w
    }

    private func referenceDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        guard !a.isEmpty, !b.isEmpty else { return d[a.count][b.count] }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    private func isID(_ w: String) -> Bool {
        let parts = w.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[0].allSatisfy(\.isLetter) && !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && $0.isNumber }
    }

    private func tolerance(_ n: Int) -> Int { n >= 8 ? 2 : n >= 4 ? 1 : 0 }

    private func reference(_ q: String, _ w: String) -> MatchKind? {
        if scalars(q) == scalars(w) { return .exact }
        let n = scalars(q).count
        let strict = n <= 3 || isID(q)
        if w.utf16.starts(with: q.utf16) { return .prefix }
        if !strict, scalars(referenceStem(q)) == scalars(referenceStem(w)) { return .form }
        if strict || isID(w) { return nil }
        var d = referenceDistance(scalars(q), scalars(w))
        if d > tolerance(n) {
            let sq = referenceStem(q)
            let sd = referenceDistance(scalars(sq), scalars(referenceStem(w)))
            if sd > tolerance(scalars(sq).count) { return nil }
            d = sd
        }
        return .typo
    }

    // MARK: tests

    @Test func matchKindEqualsTheReferenceOnRandomWords() {
        var state: UInt64 = 7
        func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33) % n
        }
        let pieces = ["a", "b", "c", "ab", "ba", "s", "es", "ed", "ing", "ä", "é", "-", "1", "stk", "x"]
        func word() -> String { (0..<(1 + next(6))).map { _ in pieces[next(pieces.count)] }.joined() }
        var kinds = Set<MatchKind>()
        for _ in 0..<20_000 {
            let q = word()
            // a word near q half of the time, so that typos and forms occur
            var w = word()
            if next(2) == 0 {
                var chars = Array(q)
                switch next(4) {
                case 0 where !chars.isEmpty: chars.remove(at: next(chars.count))
                case 1: chars.insert(pieces[next(4)].first!, at: next(chars.count + 1))
                case 2 where chars.count > 1: let i = next(chars.count - 1); chars.swapAt(i, i + 1)
                default: chars.append(contentsOf: Array(["s", "ed", "ing", "es"][next(4)]))
                }
                w = String(chars)
            }
            let got = matchKind(query: q, word: w)
            #expect(got == reference(q, w), "\(q) \(w)")
            if let got { kinds.insert(got) }
        }
        #expect(kinds == [.exact, .prefix, .form, .typo])
    }

    @Test func tolerancesCountCodePoints() {
        // "😀abc" is four code points (one wrong letter allowed), though five UTF-16 units
        #expect(matchKind(query: "😀abc", word: "😀abd") == .typo)
        #expect(matchKind(query: "abc", word: "abd") == nil)
    }

    @Test func stemsKeepShortWords() {
        #expect(["bed", "red", "is", "as", "bus", "uses", "sing", "using", "ed", "ings"].map(stem)
            == ["bed", "red", "is", "as", "bus", "use", "sing", "using", "ed", "ing"])
    }
}
