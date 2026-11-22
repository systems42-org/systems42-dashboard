import Foundation

/// Text helpers of the Go dashboard, `internal/project/common.go`. The Go regular expressions use
/// ASCII classes, so they are spelled out here and Swift's Unicode classes do not change a label.
enum Common {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed in this file.
        try! NSRegularExpression(pattern: pattern)
    }

    private static let space = "[\\t\\n\\f\\r ]"
    private static let wikilinkAlias = regex("\\[\\[[^\\]|]+\\|([^\\]]+)\\]\\]")
    private static let wikilinkPlain = regex("\\[\\[([^\\]]+)\\]\\]")
    private static let trailingParenthetical = regex("\(space)*\\([^)]*\\)\(space)*$")
    private static let mermaidDelimiters = regex("[<>\"|\\[\\]]")
    private static let whitespaceRun = regex("\(space)+")

    /// Ports `DiagramNodeID`: only ASCII letters and digits stay, "N" for nothing.
    static func diagramNodeID(_ raw: String) -> String {
        let kept = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }))
        return kept.isEmpty ? "N" : kept
    }

    /// Ports `CleanLabel`: resolves wikilinks, optionally drops a trailing parenthetical, writes "&" as
    /// " and ", strips Mermaid and HTML delimiters and collapses space.
    static func cleanLabel(_ text: String, dropParenthetical: Bool) -> String {
        var t = replace(wikilinkAlias, in: text) { match, string in string.substring(with: match.range(at: 1)) }
        t = replace(wikilinkPlain, in: t) { match, string in
            let inner = string.substring(with: match.range(at: 1))
            return String(inner.split(separator: "/", omittingEmptySubsequences: false).last ?? "")
        }
        if dropParenthetical { t = replace(trailingParenthetical, in: t) { _, _ in "" } }
        t = t.replacingOccurrences(of: "&", with: " and ")
        t = replace(mermaidDelimiters, in: t) { _, _ in "" }
        t = replace(whitespaceRun, in: t) { _, _ in " " }
        return trim(t)
    }

    /// Ports `MMEscape`: whitespace collapses, "#" and ";" become Mermaid entity codes.
    static func mmEscape(_ text: String) -> String {
        var out = ""
        for scalar in fields(text).joined(separator: " ").unicodeScalars {
            switch scalar {
            case "#": out += "#35;"
            case ";": out += "#59;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
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

    private static func replace(_ regex: NSRegularExpression, in text: String, with make: (NSTextCheckingResult, NSString) -> String) -> String {
        let string = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: string.length))
        guard !matches.isEmpty else { return text }
        var out = ""
        var position = 0
        for match in matches {
            out += string.substring(with: NSRange(location: position, length: match.range.location - position))
            out += make(match, string)
            position = match.range.location + match.range.length
        }
        return out + string.substring(from: position)
    }

    /// The first `count` characters of a text, as `firstRunes`.
    static func firstRunes(_ text: String, _ count: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        return scalars.count <= count ? text : String(String.UnicodeScalarView(scalars[..<count]))
    }

    static func runeCount(_ text: String) -> Int { text.unicodeScalars.count }
}
