import Foundation
import Systems42Kit

/// How one section's list looks: sort, filters and mode. Kept per section in the window's
/// restored state. Nothing of it is written to the wiki.
public struct ListState: Codable, Hashable, Sendable {
    public var sort: [SortKey]
    /// Selected values per field. A field with no values, or none at all, does not filter.
    public var filters: [String: Set<String>]
    /// The projection the section shows, such as "list".
    public var mode: String

    public init(sort: [SortKey] = [], filters: [String: Set<String>] = [:], mode: String) {
        self.sort = sort
        self.filters = filters
        self.mode = mode
    }
}

/// The list states of all sections as one JSON text, for `SceneStorage`.
enum ListStates {
    static func encode(_ states: [String: ListState]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(states)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Empty for text that is empty or cannot be read.
    static func decode(_ text: String) -> [String: ListState] {
        (try? JSONDecoder().decode([String: ListState].self, from: Data(text.utf8))) ?? [:]
    }

    static func updating(_ text: String, section: String, with state: ListState) -> String {
        var all = decode(text)
        all[section] = state
        return encode(all)
    }
}

/// A field name as a label: "raised-by" becomes "Raised by". A generic rule, no lookup table.
enum FieldLabel {
    static func text(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
