import Foundation

/// An Obsidian link: `[[target]]`, `[[target|label]]` or `[[target#heading|label]]`.
public struct Wikilink: Hashable, Sendable {
    /// What stands before `#` and `|`, trimmed. May hold a path such as `raw/sources/SRC-001`.
    public let target: String
    public let label: String?
    public let heading: String?

    public init(target: String, label: String?, heading: String?) {
        self.target = target
        self.label = label
        self.heading = heading
    }

    /// The last path component of `target`, which is what a link resolves by.
    public var name: String {
        let last = target.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        return last.trimmingCharacters(in: .whitespaces)
    }

    /// A link longer than this between the brackets is text. It keeps a file
    /// of nothing but `[[` linear to scan.
    private static let longestLink = 512

    private static let open = UInt8(ascii: "["), close = UInt8(ascii: "]")
    private static let pipe = UInt8(ascii: "|"), hash = UInt8(ascii: "#")

    /// Every link in `text`, in order. Same rules as the dashboard: the target
    /// holds no `]`, `|` or `#`, the heading no `]` or `|`, the label no `]`.
    public static func all(in text: String) -> [Wikilink] {
        matches(in: text).map(\.link)
    }

    /// A link and where it stands: the UTF-8 offsets of `[[` up to and including `]]`.
    public struct Match: Sendable {
        public let link: Wikilink
        public let utf8Range: Range<Int>
    }

    /// Like `all(in:)`, with the position of each link.
    public static func matches(in text: String) -> [Match] {
        let bytes = Array(text.utf8)
        var links: [Match] = []
        var i = 0
        var nextClose = -1
        while i + 1 < bytes.count {
            guard bytes[i] == open, bytes[i + 1] == open else { i += 1; continue }
            if nextClose < i + 2 {
                nextClose = bytes[(i + 2)...].firstIndex(of: close) ?? bytes.count
            }
            guard nextClose + 1 < bytes.count else { break }  // no `]]` left anywhere
            if bytes[nextClose + 1] == close, nextClose - i - 2 <= longestLink,
               let link = parse(bytes[(i + 2)..<nextClose]) {
                links.append(Match(link: link, utf8Range: i..<(nextClose + 2)))
                i = nextClose + 2
            } else {
                i += 1
            }
        }
        return links
    }

    private static func parse(_ inner: ArraySlice<UInt8>) -> Wikilink? {
        let split = inner.firstIndex { $0 == pipe || $0 == hash } ?? inner.endIndex
        let target = text(inner[..<split])
        guard !target.isEmpty else { return nil }
        var heading: String?
        var rest = inner[split...]
        if rest.first == hash {
            let end = rest.firstIndex(of: pipe) ?? rest.endIndex
            let word = text(rest.dropFirst()[..<end])
            guard !rest.dropFirst()[..<end].isEmpty else { return nil }
            heading = word
            rest = rest[end...]
        }
        var label: String?
        if rest.first == pipe {
            guard rest.count > 1 else { return nil }
            label = text(rest.dropFirst())
        }
        return Wikilink(target: target, label: label?.isEmpty == false ? label : nil, heading: heading)
    }

    private static func text(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
