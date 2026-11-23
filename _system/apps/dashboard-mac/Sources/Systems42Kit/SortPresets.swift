import Foundation

/// One column of a sort and its direction. Ascending follows the order the metamodel declares
/// for an enum field (first value first), the lifecycle order for status, else the text.
public struct SortKey: Codable, Hashable, Sendable {
    public let field: String
    public var ascending: Bool

    public init(field: String, ascending: Bool = true) {
        self.field = field
        self.ascending = ascending
    }
}

/// A named ordering of a list (FR-021).
public struct SortPreset: Hashable, Sendable {
    public let label: String
    public let keys: [SortKey]
}

/// How the lists of the app sort a type (FR-021). These belong to the app, not to the
/// metamodel (CON-006): the metamodel knows nothing about sorting. The labels and keys match the
/// Go dashboard's `sortPresets`. The Go lists take the direction from the column: the columns
/// that sort descending first are `decided` and the ratings, whose numeric rank puts the
/// strongest value first. In the declared order of the enum, that is ascending here.
enum SortPresets {
    private static func ascending(_ label: String, _ fields: String...) -> SortPreset {
        SortPreset(label: label, keys: fields.map { SortKey(field: $0) })
    }

    static let byType: [String: [SortPreset]] = [
        "functional-requirement": [ascending("Priority › release › order", "priority", "release", "order")],
        "issue": [ascending("Status › severity", "status", "severity")],
        "decision-record": [SortPreset(label: "Newest first", keys: [SortKey(field: "decided", ascending: false)])],
        "domain-term": [ascending("A to Z", "title")],
        "stakeholder": [ascending("Influence › interest", "influence", "interest")],
        "quality-requirement": [ascending("Priority", "priority")],
    ]
}

extension Metamodel {
    /// The sort presets of a type, the first one is the default. Empty for a type without presets.
    public func sortPresets(for type: String) -> [SortPreset] {
        SortPresets.byType[type] ?? []
    }
}
