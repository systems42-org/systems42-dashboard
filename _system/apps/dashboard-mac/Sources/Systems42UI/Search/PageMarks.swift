import SwiftUI
import Systems42Kit

/// The words to mark in a page opened from search results (FR-007).
/// A word of the page is marked when a query word matches it as the search does: as typed, as a
/// word form or as a typo. When the hit's passage shows which words matched, only query words
/// that match one of them count, so filler words such as "what" stay unmarked.
public struct PageMarks: Equatable, Sendable {
    /// The longest word the marks compare.
    private static let longestWord = 64

    public let words: [String]
    private let used: [String]

    public init(words: [String], matchedInPassage: [String]) {
        self.words = words
        let matched = matchedInPassage.map { $0.lowercased() }.filter { !$0.isEmpty && $0.count <= Self.longestWord }
        used = matched.isEmpty ? words : words.filter { q in matched.contains { matchKind(query: q, word: $0) != nil } }
    }

    public var isEmpty: Bool { used.isEmpty }

    /// The query words in lower case, without repeats. Plain splitting at everything that is no letter or digit.
    public static func words(of query: String) -> [String] {
        var out: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty, current.count <= longestWord, !out.contains(current) { out.append(current) }
            current = ""
        }
        for ch in query.prefix(SearchLimits.longestQuery) {
            if ch.isLetter || ch.isNumber { current += ch.lowercased() } else { flush() }
        }
        flush()
        return out
    }

    public func matches(_ word: String) -> Bool {
        guard !used.isEmpty, !word.isEmpty, word.count <= Self.longestWord else { return false }
        let low = word.lowercased()
        return used.contains { matchKind(query: $0, word: low) != nil }
    }

    /// The text with every matching word marked. Links, emphasis and other attributes stay.
    public func apply(to text: AttributedString) -> AttributedString {
        guard !used.isEmpty else { return text }
        var ranges: [Range<AttributedString.Index>] = []
        var start: AttributedString.Index?
        var word = ""
        let characters = text.characters
        func flush(_ end: AttributedString.Index) {
            if let s = start, matches(word) { ranges.append(s..<end) }
            start = nil
            word = ""
        }
        for index in characters.indices {
            let ch = characters[index]
            if ch.isLetter || ch.isNumber {
                if start == nil { start = index }
                word.append(ch)
            } else {
                flush(index)
            }
        }
        flush(characters.endIndex)
        var result = text
        for range in ranges { result[range].backgroundColor = Color.yellow.opacity(0.45) }
        return result
    }
}
