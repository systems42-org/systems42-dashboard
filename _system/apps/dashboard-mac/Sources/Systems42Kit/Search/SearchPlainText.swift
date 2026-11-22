import Foundation

/// The reader-visible plain text of a page body, as the search index holds it.
///
/// Ports `Plain` of `_system/apps/dashboard/internal/search/search.go` with the helpers it
/// calls (`UnwrapProse`, `DropFollows`, `ReplaceWikilinks`, `stripSearchEmphasis`). Go's
/// regular expressions are RE2: `\s`, `\w` and `\d` are ASCII only and the engine runs in linear
/// time. To keep both properties, every expression is written out as a scanner over UTF-8 bytes.
/// The syntax characters are ASCII, so a byte scan cannot split a character. Each scanner names
/// the expression it replaces.
enum PlainText {
    typealias Bytes = [UInt8]

    /// What the link texts need from the store: the title of each page by stem, and the source records.
    struct Context {
        let titles: [String: String]
        let names: Names
    }

    static func plain(body: String, context: Context) -> String {
        var text = Bytes(body.utf8)
        text = replaceCRLF(text)
        text = dropFollows(text)
        text = unwrapProse(text)
        text = replaceWikilinks(text, context)
        text = replaceMarkdownLinks(text)
        text = replaceHTMLTags(text)

        var kept: [Bytes] = []
        for var line in splitLines(text) {
            if trimSpace(line).starts(with: Array("```".utf8)) || isTableSeparator(line) || isHeadingLine(line) { continue }
            line = removeLeadLabel(line)
            line = removeLineMarks(line)
            line = stripEmphasis(line).map { $0 == pipe ? space : $0 }
            line = trimSpace(collapseSpace(line))
            if !line.isEmpty && line != Array("---".utf8) { kept.append(line) }
        }
        return String(decoding: join(kept), as: UTF8.self)
    }

    // MARK: bytes

    private static let newline: UInt8 = 0x0A, space: UInt8 = 0x20, tab: UInt8 = 0x09, pipe: UInt8 = 0x7C
    private static let hash: UInt8 = 0x23, star: UInt8 = 0x2A, open: UInt8 = 0x5B, close: UInt8 = 0x5D
    private static let paren: UInt8 = 0x28, parenClose: UInt8 = 0x29, angle: UInt8 = 0x3C, angleClose: UInt8 = 0x3E
    private static let backtick: UInt8 = 0x60, tilde: UInt8 = 0x7E, bang: UInt8 = 0x21

    /// RE2 `\s`: tab, newline, form feed, carriage return, space.
    private static func isWS(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D }

    private static func isSpaceOrTab(_ b: UInt8) -> Bool { b == space || b == tab }

    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    /// RE2 `[\w-]`.
    private static func isNameByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x2D
    }

    private static func leadingWS(_ line: Bytes) -> Int {
        var k = 0
        while k < line.count, isWS(line[k]) { k += 1 }
        return k
    }

    private static func splitLines(_ text: Bytes) -> [Bytes] {
        text.split(separator: newline, omittingEmptySubsequences: false).map(Array.init)
    }

    private static func join(_ lines: [Bytes]) -> Bytes {
        Array(lines.joined(separator: [newline]))
    }

    /// Go `strings.TrimSpace`: Unicode white space at both ends.
    private static func trimSpace(_ b: Bytes) -> Bytes {
        if let first = b.first, let last = b.last, first > 0x20, first < 0x80, last > 0x20, last < 0x80 { return b }
        return Bytes(String(decoding: b, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }

    /// `trimSpace(b).isEmpty` without a copy: stops at the first character that is no white space.
    private static func isBlank(_ b: Bytes) -> Bool {
        var i = 0
        while i < b.count {
            let c = b[i]
            if c < 0x80 {
                if !(c == 0x20 || (c >= 0x09 && c <= 0x0D)) { return false }
                i += 1
            } else {
                let length = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : 2
                let end = Swift.min(b.count, i + length)
                let scalar = String(decoding: b[i..<end], as: UTF8.self).unicodeScalars.first
                guard let scalar, scalar.properties.isWhitespace else { return false }
                i = end
            }
        }
        return true
    }

    private static func collapseSpace(_ b: Bytes) -> Bytes {
        var out = Bytes()
        out.reserveCapacity(b.count)
        var inRun = false
        for c in b {
            if isWS(c) {
                if !inRun { out.append(space) }
                inRun = true
            } else {
                out.append(c)
                inRun = false
            }
        }
        return out
    }

    private static func replaceCRLF(_ b: Bytes) -> Bytes {
        guard b.contains(0x0D) else { return b }
        var out = Bytes()
        out.reserveCapacity(b.count)
        for (i, c) in b.enumerated() where !(c == 0x0D && i + 1 < b.count && b[i + 1] == newline) { out.append(c) }
        return out
    }

    /// `nextIndex(b, test)[i]` is the first index at or after `i` whose byte passes `test`, or `b.count`.
    private static func nextIndex(_ b: Bytes, _ test: (UInt8) -> Bool) -> [Int32] {
        var next = [Int32](repeating: Int32(b.count), count: b.count + 1)
        var i = b.count - 1
        while i >= 0 {
            next[i] = test(b[i]) ? Int32(i) : next[i + 1]
            i -= 1
        }
        return next
    }

    // MARK: line patterns

    /// `tableSepRE`: `^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$`.
    static func isTableSeparator(_ line: Bytes) -> Bool {
        let n = line.count
        var i = 0
        func skipWS() { while i < n, isWS(line[i]) { i += 1 } }
        func cell() -> Bool {
            if i < n, line[i] == 0x3A { i += 1 }
            let start = i
            while i < n, line[i] == 0x2D { i += 1 }
            guard i - start >= 3 else { return false }
            if i < n, line[i] == 0x3A { i += 1 }
            skipWS()
            return true
        }
        skipWS()
        if i < n, line[i] == pipe { i += 1 }
        skipWS()
        guard cell() else { return false }
        while i < n, line[i] == pipe {
            i += 1
            skipWS()
            if i == n { return true }
            guard cell() else { return false }
        }
        return i == n
    }

    /// `listStartRE`: `^\s*([-*+]|\d+[.)])\s`.
    static func isListStart(_ line: Bytes) -> Bool {
        let k = leadingWS(line)
        guard k < line.count else { return false }
        let c = line[k]
        if c == 0x2D || c == 0x2A || c == 0x2B { return k + 1 < line.count && isWS(line[k + 1]) }
        guard isDigit(c) else { return false }
        var j = k
        while j < line.count, isDigit(line[j]) { j += 1 }
        return j + 1 < line.count && (line[j] == 0x2E || line[j] == parenClose) && isWS(line[j + 1])
    }

    /// `blockStartRE`: a list start, `#`, `>`, `|`, a fence, `<` after white space, four or more
    /// white-space characters before text, or a leading tab.
    static func isBlockStart(_ line: Bytes) -> Bool {
        if line.first == tab { return true }
        let k = leadingWS(line)
        guard k < line.count else { return false }
        switch line[k] {
        case hash, angleClose, pipe, angle: return true
        case backtick: if line[k...].starts(with: [backtick, backtick, backtick]) { return true }
        case tilde: if line[k...].starts(with: [tilde, tilde, tilde]) { return true }
        default: break
        }
        return isListStart(line) || k >= 4
    }

    /// `fenceRE`: ``^ {0,3}(`{3,}|~{3,})``. Returns the fence character and the length of the run.
    private static func fence(_ line: Bytes) -> (char: UInt8, length: Int)? {
        var i = 0
        while i < 3, i < line.count, line[i] == space { i += 1 }
        guard i < line.count, line[i] == backtick || line[i] == tilde else { return nil }
        let c = line[i]
        var j = i
        while j < line.count, line[j] == c { j += 1 }
        return j - i >= 3 ? (c, j - i) : nil
    }

    /// `fencedLines`.
    private static func fencedLines(_ lines: [Bytes]) -> [Bool] {
        var out = [Bool](repeating: false, count: lines.count)
        var open: (char: UInt8, length: Int)?
        for (i, line) in lines.enumerated() {
            let found = fence(line)
            if let current = open {
                if let found, found.char == current.char, found.length >= current.length { open = nil }
                out[i] = true
            } else if let found {
                open = found
                out[i] = true
            }
        }
        return out
    }

    /// `headingLineRE`: `^\s*(?:#{1,6}\s|>\s*\[![\w-]+\]|\*\*[^*]+\*\*\s*$)`.
    private static func isHeadingLine(_ line: Bytes) -> Bool {
        let n = line.count
        var i = leadingWS(line)
        guard i < n else { return false }
        switch line[i] {
        case hash:
            var j = i
            while j < n, line[j] == hash { j += 1 }
            return j - i <= 6 && j < n && isWS(line[j])
        case angleClose:
            i += 1
            while i < n, isWS(line[i]) { i += 1 }
            return calloutMark(line, i) != nil
        case star:
            guard i + 1 < n, line[i + 1] == star else { return false }
            var j = i + 2
            while j < n, line[j] != star { j += 1 }
            guard j > i + 2, j + 1 < n, line[j + 1] == star else { return false }
            j += 2
            while j < n, isWS(line[j]) { j += 1 }
            return j == n
        default:
            return false
        }
    }

    /// `\[![\w-]+\]` at `i`: the index after it, or nil.
    private static func calloutMark(_ line: Bytes, _ i: Int) -> Int? {
        let n = line.count
        guard i + 1 < n, line[i] == open, line[i + 1] == bang else { return nil }
        var j = i + 2
        while j < n, isNameByte(line[j]) { j += 1 }
        return j > i + 2 && j < n && line[j] == close ? j + 1 : nil
    }

    /// `leadLabelRE` replaced by `$1`: `^(\s*(?:[-*+]\s+)?)\*\*[^*]{1,60}[.:]\*\*\s+`.
    private static func removeLeadLabel(_ line: Bytes) -> Bytes {
        let n = line.count
        var i = leadingWS(line)
        var keep = i
        if i < n, line[i] == 0x2D || line[i] == star || line[i] == 0x2B, i + 1 < n, isWS(line[i + 1]) {
            var j = i + 1
            while j < n, isWS(line[j]) { j += 1 }
            i = j
            keep = j
        }
        guard i + 1 < n, line[i] == star, line[i + 1] == star else { return line }
        let labelStart = i + 2
        var p = labelStart
        while p < n, line[p] != star { p += 1 }
        guard p > labelStart, p + 1 < n, line[p + 1] == star, line[p - 1] == 0x2E || line[p - 1] == 0x3A else { return line }
        let runes = line[labelStart..<(p - 1)].reduce(0) { $0 + (($1 & 0xC0) == 0x80 ? 0 : 1) }
        guard runes >= 1, runes <= 60 else { return line }
        var end = p + 2
        guard end < n, isWS(line[end]) else { return line }
        while end < n, isWS(line[end]) { end += 1 }
        return Array(line[..<keep]) + Array(line[end...])
    }

    /// `lineMarkRE` removed: ``^\s*(?:#{1,6}\s+|>\s*(?:\[![\w-]+\][-+]?\s*)?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+``.
    private static func removeLineMarks(_ line: Bytes) -> Bytes {
        let n = line.count
        var j = leadingWS(line)
        var items = 0
        func skipWS() { while j < n, isWS(line[j]) { j += 1 } }
        loop: while j < n {
            let c = line[j]
            switch c {
            case hash:
                var k = j
                while k < n, line[k] == hash { k += 1 }
                guard k - j <= 6, k < n, isWS(line[k]) else { break loop }
                j = k
                skipWS()
            case angleClose:
                j += 1
                skipWS()
                if var k = calloutMark(line, j) {
                    if k < n, line[k] == 0x2D || line[k] == 0x2B { k += 1 }
                    j = k
                    skipWS()
                }
            case 0x2D, star, 0x2B:
                guard j + 1 < n, isWS(line[j + 1]) else { break loop }
                j += 1
                skipWS()
                if j + 3 < n, line[j] == open, line[j + 1] == space || line[j + 1] == 0x78 || line[j + 1] == 0x58,
                   line[j + 2] == close, isWS(line[j + 3]) {
                    j += 3
                    skipWS()
                }
            case 0x30...0x39:
                var k = j
                while k < n, isDigit(line[k]) { k += 1 }
                guard k + 1 < n, line[k] == 0x2E || line[k] == parenClose, isWS(line[k + 1]) else { break loop }
                j = k + 1
                skipWS()
            default:
                break loop
            }
            items += 1
        }
        return items == 0 ? line : Array(line[j...])
    }

    // MARK: emphasis

    /// Go `unicode.IsLetter(r) || unicode.IsDigit(r) || r == '_'`.
    private static func isWordRune(_ u: Unicode.Scalar) -> Bool {
        u == "_" || Search.isLetter(u) || u.properties.generalCategory == .decimalNumber
    }

    /// `stripSearchEmphasis`: ``\*\*|__|~~|` `` and a `*` that touches a word on one side only.
    private static func stripEmphasis(_ line: Bytes) -> Bytes {
        var out = Bytes()
        out.reserveCapacity(line.count)
        var i = 0
        let n = line.count
        while i < n {
            let c = line[i]
            let twice = i + 1 < n && line[i + 1] == c
            if c == backtick { i += 1; continue }
            if twice, c == star || c == 0x5F || c == tilde { i += 2; continue }
            out.append(c)
            i += 1
        }
        guard out.contains(star) else { return out }
        let runes = Array(String(decoding: out, as: UTF8.self).unicodeScalars)
        var kept = String.UnicodeScalarView()
        for (i, r) in runes.enumerated() {
            if r == "*" {
                let prevWord = i > 0 && isWordRune(runes[i - 1])
                let prevNonSpace = i > 0 && !runes[i - 1].properties.isWhitespace
                let nextWord = i + 1 < runes.count && isWordRune(runes[i + 1])
                let nextNonSpace = i + 1 < runes.count && !runes[i + 1].properties.isWhitespace
                if (!prevWord && nextNonSpace) || (prevNonSpace && !nextWord) { continue }
            }
            kept.append(r)
        }
        return Bytes(String(kept).utf8)
    }

    // MARK: wikilinks

    struct WikilinkMatch {
        let range: Range<Int>
        let target: Range<Int>
        let alias: Range<Int>?
    }

    /// `wikilinkRE`: `\[\[([^\]\|#]+)(?:#[^\]\|]+)?(?:\|([^\]]+))?\]\]`.
    /// The next-delimiter tables keep the scan linear on input such as `[[[[[[`. A match holds index
    /// ranges, so nothing is copied before the closing `]]` has matched.
    static func wikilinks(in b: Bytes) -> [WikilinkMatch] {
        let n = b.count
        guard n >= 5 else { return [] }
        let nextTargetEnd = nextIndex(b) { $0 == close || $0 == pipe || $0 == hash }
        let nextBar = nextIndex(b) { $0 == close || $0 == pipe }
        let nextClose = nextIndex(b) { $0 == close }
        var out: [WikilinkMatch] = []
        var i = 0
        while i + 1 < n {
            guard b[i] == open, b[i + 1] == open else { i += 1; continue }
            let t0 = i + 2
            var p = Int(nextTargetEnd[t0])
            guard p > t0 else { i += 1; continue }
            let target = t0..<p
            if p < n, b[p] == hash {
                let h = Int(nextBar[p + 1])
                guard h > p + 1 else { i += 1; continue }
                p = h
            }
            var alias: Range<Int>?
            if p < n, b[p] == pipe {
                let c = Int(nextClose[p + 1])
                guard c > p + 1 else { i += 1; continue }
                alias = (p + 1)..<c
                p = c
            }
            guard p + 1 < n, b[p] == close, b[p + 1] == close else { i += 1; continue }
            out.append(WikilinkMatch(range: i..<(p + 2), target: target, alias: alias))
            i = p + 2
        }
        return out
    }

    /// `ReplaceWikilinks` with the function `Plain` passes.
    private static func replaceWikilinks(_ b: Bytes, _ context: Context) -> Bytes {
        let found = wikilinks(in: b)
        guard !found.isEmpty else { return b }
        var out = Bytes()
        var last = 0
        for m in found {
            out.append(contentsOf: b[last..<m.range.lowerBound])
            let target = trimSpace(Array(b[m.target]))
            let alias = trimSpace(m.alias.map { Array(b[$0]) } ?? [])
            out.append(contentsOf: linkText(target: target, alias: alias, context))
            last = m.range.upperBound
        }
        out.append(contentsOf: b[last...])
        return out
    }

    private static func linkText(target targetBytes: Bytes, alias: Bytes, _ context: Context) -> Bytes {
        if !alias.isEmpty { return alias }
        let target = String(decoding: targetBytes, as: UTF8.self)
        let base = String(decoding: targetBytes.split(separator: 0x2F, omittingEmptySubsequences: false).last ?? [], as: UTF8.self)
        if context.names.isSource(target: target, name: base) {
            if let id = context.names.sourceIds[base] { return Bytes(id.utf8) }
            return sourceIDPrefix(Bytes(base.utf8))   // `^[A-Z]+-\d+`
        }
        if let title = context.titles[base] { return Bytes(title.utf8) }
        return targetBytes
    }

    /// `sourceIDRE.FindString`: `^[A-Z]+-\d+`, or nothing.
    private static func sourceIDPrefix(_ b: Bytes) -> Bytes {
        var i = 0
        while i < b.count, b[i] >= 0x41, b[i] <= 0x5A { i += 1 }
        guard i > 0, i < b.count, b[i] == 0x2D else { return [] }
        var j = i + 1
        while j < b.count, isDigit(b[j]) { j += 1 }
        return j > i + 1 ? Array(b[..<j]) : []
    }

    // MARK: links and tags

    /// `mdLinkRE` replaced by `$1`: `!?\[([^\]]*)\]\([^)]*\)`.
    private static func replaceMarkdownLinks(_ b: Bytes) -> Bytes {
        guard b.contains(open) else { return b }
        let n = b.count
        let nextClose = nextIndex(b) { $0 == close }
        let nextParen = nextIndex(b) { $0 == parenClose }
        var out = Bytes()
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            var bracket = -1
            if b[i] == bang, i + 1 < n, b[i + 1] == open { bracket = i + 1 } else if b[i] == open { bracket = i }
            if bracket >= 0 {
                let c = Int(nextClose[bracket + 1])
                if c + 1 < n, b[c + 1] == paren {
                    let d = Int(nextParen[c + 2])
                    if d < n {
                        out.append(contentsOf: b[(bracket + 1)..<c])
                        i = d + 1
                        continue
                    }
                }
            }
            out.append(b[i])
            i += 1
        }
        return out
    }

    /// `htmlTagRE` replaced by a space: `<[^>]+>`.
    private static func replaceHTMLTags(_ b: Bytes) -> Bytes {
        guard b.contains(angle) else { return b }
        let n = b.count
        var out = Bytes()
        out.reserveCapacity(n)
        var close = -1   // the next `>` found so far, scanned once from left to right
        var i = 0
        while i < n {
            if b[i] == angle {
                if close <= i {
                    close = i + 1
                    while close < n, b[close] != angleClose { close += 1 }
                }
                if close >= n { out.append(contentsOf: b[i...]); break }
                if close > i + 1 {
                    out.append(space)
                    i = close + 1
                    continue
                }
            }
            out.append(b[i])
            i += 1
        }
        return out
    }

    // MARK: follows notes and prose

    private static let followsWord = Array("follows".utf8)

    /// `followsRE`: `^ {0,3}>[ \t]*follows[ \t]+(\S.*?)[ \t]*$`. Returns the captured text.
    private static func followsText(_ line: Bytes) -> Bytes? {
        let n = line.count
        var i = 0
        while i < 3, i < n, line[i] == space { i += 1 }
        guard i < n, line[i] == angleClose else { return nil }
        i += 1
        while i < n, isSpaceOrTab(line[i]) { i += 1 }
        guard line[i...].starts(with: followsWord) else { return nil }
        i += followsWord.count
        let gap = i
        while i < n, isSpaceOrTab(line[i]) { i += 1 }
        guard i > gap, i < n, !isWS(line[i]) else { return nil }
        var end = n
        while end > i + 1, isSpaceOrTab(line[end - 1]) { end -= 1 }
        return Array(line[i..<end])
    }

    /// `followsNotes`: the lines of `> follows ...` notes outside fences.
    private static func followsLines(_ lines: [Bytes]) -> Set<Int> {
        let fenced = fencedLines(lines)
        var out = Set<Int>()
        for (i, line) in lines.enumerated() where !fenced[i] {
            guard let text = followsText(line) else { continue }
            if wikilinks(in: text).isEmpty {
                let fields = String(decoding: text, as: UTF8.self).unicodeScalars.split { $0.properties.isWhitespace }
                if fields.count > 6 || text.contains(where: { [0x2E, 0x21, 0x3F, 0x3B, 0x3A].contains($0) }) { continue }
            }
            out.insert(i)
        }
        return out
    }

    /// `DropFollows`.
    private static func dropFollows(_ body: Bytes) -> Bytes {
        let lines = splitLines(body)
        let drop = followsLines(lines)
        guard !drop.isEmpty else { return body }
        return join(lines.enumerated().filter { !drop.contains($0.offset) }.map(\.element))
    }

    /// `UnwrapProse`: joins hard-wrapped prose lines into one line per paragraph and puts a blank
    /// line between a prose line and a following list.
    private static func unwrapProse(_ body: Bytes) -> Bytes {
        let lines = splitLines(body)
        var tableLines = Set<Int>()
        for (i, line) in lines.enumerated() where line.contains(pipe) && isTableSeparator(line) {
            tableLines.insert(i)
            if i > 0, lines[i - 1].contains(pipe) { tableLines.insert(i - 1) }
            var j = i + 1
            // A line already marked belongs to an earlier table run that ends where this one does.
            while j < lines.count, !tableLines.contains(j), !isBlank(lines[j]), lines[j].contains(pipe) {
                tableLines.insert(j)
                j += 1
            }
        }

        let fenced = fencedLines(lines)
        var out: [Bytes] = []
        var inList = false
        for (idx, line) in lines.enumerated() {
            if fenced[idx] {
                inList = false
                out.append(line)
                continue
            }
            if isBlank(line) {
                inList = false
                out.append(line)
                continue
            }
            let listStart = isListStart(line)
            let blockStart = listStart || isBlockStart(line) || tableLines.contains(idx)

            if inList && !blockStart {
                out.append(Array(line.drop { isSpaceOrTab($0) }))
                continue
            }
            // `prev` is not kept: a second reference would make the append below copy the paragraph
            let (prevIsProse, prevEndsInTwoSpaces) = out.last.map { prev in
                (!isBlank(prev) && !isBlockStart(prev) && !tableLines.contains(idx - 1) && !inList,
                 prev.count >= 2 && prev[prev.count - 1] == space && prev[prev.count - 2] == space)
            } ?? (false, false)
            if blockStart {
                if prevIsProse && listStart { out.append([]) }
                out.append(line)
                inList = listStart
                continue
            }
            if prevIsProse && !prevEndsInTwoSpaces {
                while let last = out[out.count - 1].last, isSpaceOrTab(last) { out[out.count - 1].removeLast() }
                out[out.count - 1].append(space)
                out[out.count - 1].append(contentsOf: trimSpace(line))
            } else {
                out.append(line)
            }
        }
        return join(out)
    }
}
