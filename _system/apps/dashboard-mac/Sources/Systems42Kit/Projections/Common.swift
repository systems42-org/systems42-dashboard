import Foundation

/// Text helpers of the Go dashboard, `internal/project/common.go`, and the two functions through which
/// page text enters a Mermaid text: `label` for text in a label and `NodeIDs` for node ids.
/// Go's regular expressions are replaced by linear scans: Foundation's engine backtracks, and a long
/// title of `(` or `[[` takes seconds. Every label is cut to `longestLabel` first as well.
enum Common {
    /// The longest label in characters. A longer text is cut and ends in an ellipsis.
    static let longestLabel = 300
    static let ellipsis: Unicode.Scalar = "…"

    /// What a label function writes for characters that would end a label or start a Mermaid statement.
    /// `"`, `<`, `>`, `|`, `[` and `]` are removed as in Go.
    private static let labelEntities: [Unicode.Scalar: String] = [
        ";": "#59;", "%": "#37;", "`": "#96;", "{": "#123;", "}": "#125;",
    ]
    /// The same for a text that sits after a colon or between quotes in an edge or a message.
    private static let messageEntities: [Unicode.Scalar: String] = [
        "#": "#35;", ";": "#59;", "%": "#37;", "`": "#96;", "<": "#60;", ">": "#62;",
    ]
    private static let mermaidDelimiters: Set<Unicode.Scalar> = ["<", ">", "\"", "|", "[", "]"]

    /// Go's `\s`.
    private static func isRegexSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\u{0C}" || scalar == "\r"
    }

    /// Ports `DiagramNodeID`: only ASCII letters and digits stay, "N" for nothing.
    static func diagramNodeID(_ raw: String) -> String {
        let kept = String(String.UnicodeScalarView(raw.unicodeScalars.prefix(longestLabel * 4).filter {
            ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }))
        return kept.isEmpty ? "N" : kept
    }

    /// The label function: text of a page (id, title, field value) as safe label text. Same as
    /// `cleanLabel` without dropping a parenthetical.
    static func label(_ text: String) -> String {
        cleanLabel(text, dropParenthetical: false)
    }

    /// Ports `CleanLabel`: resolves wikilinks, optionally drops a trailing parenthetical, writes "&" as
    /// " and ", strips Mermaid and HTML delimiters and collapses space. It also cuts the text to
    /// `longestLabel` and writes `;`, `%`, backticks and braces as entity codes, so no page text can
    /// close a label or start a statement.
    static func cleanLabel(_ text: String, dropParenthetical: Bool) -> String {
        var scalars = cut(Array(text.unicodeScalars.prefix(longestLabel + 1)))
        scalars = resolveAliasLinks(scalars)
        scalars = resolvePlainLinks(scalars)
        if dropParenthetical { scalars = dropTrailingParenthetical(scalars) }
        var out: [Unicode.Scalar] = []
        var pendingSpace = false
        func push(_ scalar: Unicode.Scalar) {
            if pendingSpace && !out.isEmpty { out.append(" ") }
            pendingSpace = false
            out.append(scalar)
        }
        for scalar in expandAmpersands(scalars) where !mermaidDelimiters.contains(scalar) {
            if isRegexSpace(scalar) { pendingSpace = true; continue }
            if let entity = labelEntities[scalar] { entity.unicodeScalars.forEach(push) } else { push(scalar) }
        }
        return trim(String(String.UnicodeScalarView(out)))
    }

    private static func cut(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.count > longestLabel ? Array(scalars.prefix(longestLabel - 1)) + [ellipsis] : scalars
    }

    private static func expandAmpersands(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.flatMap { $0 == "&" ? Array(" and ".unicodeScalars) : [$0] }
    }

    /// `\[\[[^\]|]+\|([^\]]+)\]\]` replaced by the group. Scans left to right.
    private static func resolveAliasLinks(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < s.count {
            if let (end, label) = aliasLink(s, at: i) {
                out += s[label]
                i = end
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return out
    }

    private static func aliasLink(_ s: [Unicode.Scalar], at i: Int) -> (end: Int, label: Range<Int>)? {
        guard i + 1 < s.count, s[i] == "[", s[i + 1] == "[" else { return nil }
        var j = i + 2
        while j < s.count, s[j] != "]", s[j] != "|" { j += 1 }
        guard j > i + 2, j < s.count, s[j] == "|" else { return nil }
        let start = j + 1
        j = start
        while j < s.count, s[j] != "]" { j += 1 }
        guard j > start, j + 1 < s.count, s[j + 1] == "]" else { return nil }
        return (j + 2, start..<j)
    }

    /// `\[\[([^\]]+)\]\]` replaced by the last `/` part of the group.
    private static func resolvePlainLinks(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < s.count {
            if i + 1 < s.count, s[i] == "[", s[i + 1] == "[" {
                var j = i + 2
                while j < s.count, s[j] != "]" { j += 1 }
                if j == s.count {  // no `]` is left, so no later link can close either
                    out += s[i...]
                    break
                }
                if j > i + 2, j + 1 < s.count, s[j + 1] == "]" {
                    let inner = s[(i + 2)..<j]
                    let lastSlash = inner.lastIndex(of: "/")
                    out += lastSlash.map { inner[($0 + 1)...] } ?? inner
                    i = j + 2
                    continue
                }
            }
            out.append(s[i])
            i += 1
        }
        return out
    }

    /// `\s*\([^)]*\)\s*$` removed.
    private static func dropTrailingParenthetical(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var end = s.count
        while end > 0, isRegexSpace(s[end - 1]) { end -= 1 }
        guard end > 0, s[end - 1] == ")" else { return s }
        var previous = end - 2
        while previous >= 0, s[previous] != ")" { previous -= 1 }
        guard let open = ((previous + 1)..<(end - 1)).first(where: { s[$0] == "(" }) else { return s }
        var start = open
        while start > 0, isRegexSpace(s[start - 1]) { start -= 1 }
        return Array(s[..<start])
    }

    /// Ports `MMEscape`: whitespace collapses, "#" and ";" become Mermaid entity codes. The text is cut
    /// to `longestLabel`, and `%`, backticks, `<` and `>` are written as entity codes too.
    static func mmEscape(_ text: String) -> String {
        var out = ""
        for scalar in cutText(fields(String(String.UnicodeScalarView(text.unicodeScalars.prefix(longestLabel * 4))))
            .joined(separator: " ")).unicodeScalars {
            if let entity = messageEntities[scalar] { out += entity } else { out.unicodeScalars.append(scalar) }
        }
        return out
    }

    /// The text cut to `longestLabel` characters, with an ellipsis.
    static func cutText(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars.prefix(longestLabel + 1))
        return String(String.UnicodeScalarView(cut(scalars)))
    }

    /// Ports `EdgeText`.
    static func edgeText(_ text: String) -> String {
        mmEscape(text).replacingOccurrences(of: "\"", with: "'")
    }

    /// Go's `strings.Fields`: the runs of non-space characters.
    static func fields(_ text: String) -> [String] {
        text.unicodeScalars.split(whereSeparator: { $0.properties.isWhitespace }).map { String(String.UnicodeScalarView($0)) }
    }

    /// Go's `strings.TrimSpace`.
    static func trim(_ text: String) -> String {
        var scalars = Substring(text).unicodeScalars[...]
        while let first = scalars.first, first.properties.isWhitespace { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.properties.isWhitespace { scalars = scalars.dropLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Go's `string <` : by UTF-8 bytes.
    static func less(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    /// The first `count` characters of a text, as `firstRunes`.
    static func firstRunes(_ text: String, _ count: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        return scalars.count <= count ? text : String(String.UnicodeScalarView(scalars[..<count]))
    }

    static func runeCount(_ text: String) -> Int { text.unicodeScalars.count }
}
