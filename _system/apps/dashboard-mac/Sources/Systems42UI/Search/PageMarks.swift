import SwiftUI
import Systems42Kit

/// The words to mark in a page opened from search results (FR-007).
///
/// A page word is marked when a query word matches it as the search does: as typed, as a word form
/// or as a typo. When the hit's passage shows which words matched, only query words that match one
/// of them count, so filler words such as "what" stay unmarked. The query limits are the ranker's.
///
/// `compute` decides each distinct page word once and runs off the main actor. The views only look
/// a word up in the finished set, so drawing a page never runs the matcher.
public struct PageMarks: Equatable, Sendable {
    /// The longest word that is compared. A longer one is never marked.
    static let longestWord = 64
    /// How many page words `compute` reads between two checks for cancellation.
    private static let checkEvery = 4096

    /// The query words that count, lower case.
    public let words: [String]
    /// The lower-case page words to mark.
    let marked: Set<String>

    public static let none = PageMarks(words: [], marked: [])

    init(words: [String], marked: Set<String>) {
        self.words = words
        self.marked = marked
    }

    public var isEmpty: Bool { marked.isEmpty }

    /// The query words in lower case, without repeats: the first 200 characters of the query, the first 16 words.
    public static func words(of query: String) -> [String] {
        var out: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty, current.count <= longestWord, !out.contains(current) { out.append(current) }
            current = ""
        }
        for ch in String(String.UnicodeScalarView(query.unicodeScalars.prefix(SearchLimit.longestQuery))) {
            if isWordCharacter(ch) { current += ch.lowercased() } else { flush() }
        }
        flush()
        return Array(out.prefix(SearchLimit.mostQueryWords))
    }

    /// The one rule for what belongs to a word, for the query, the page text and the shown text.
    /// It works on characters, so a letter with a separate accent is one word character.
    static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// Reads all words of `text` once. A cancelled run gives no marks.
    public static func compute(text: String, query: String, matchedInPassage: [String]) -> PageMarks {
        let all = words(of: query)
        let matched = matchedInPassage.map { $0.lowercased() }.filter { !$0.isEmpty && $0.count <= longestWord }
        let used = matched.isEmpty ? all : all.filter { q in matched.contains { matchKind(query: q, word: $0) != nil } }
        guard !used.isEmpty else { return PageMarks(words: used, marked: []) }
        var decided: [String: Bool] = [:]
        var marked = Set<String>()
        var word = ""
        var length = 0
        var read = 0
        func flush() {
            defer { word = ""; length = 0 }
            guard length > 0, length <= longestWord else { return }
            let low = word.lowercased()
            if decided[low] == nil {
                let hit = used.contains { matchKind(query: $0, word: low) != nil }
                decided[low] = hit
                if hit { marked.insert(low) }
            }
        }
        for ch in text {
            if isWordCharacter(ch) {
                length += 1
                if length <= longestWord { word.append(ch) }
            } else if length > 0 {
                flush()
                read += 1
                if read % checkEvery == 0, Task.isCancelled { return PageMarks(words: used, marked: []) }
            }
        }
        flush()
        return PageMarks(words: used, marked: marked)
    }

    public func matches(_ word: String) -> Bool {
        !marked.isEmpty && word.count <= Self.longestWord && marked.contains(word.lowercased())
    }

    /// The text with every marked word marked. Links, emphasis and other attributes stay.
    public func apply(to text: AttributedString) -> AttributedString {
        guard !marked.isEmpty else { return text }
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
            if Self.isWordCharacter(ch) {
                if start == nil { start = index }
                if word.count <= Self.longestWord { word.append(ch) }
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
