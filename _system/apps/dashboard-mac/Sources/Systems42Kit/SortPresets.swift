import Foundation

/// How the lists of the app sort a type (FR-021). These belong to the app, not to the
/// metamodel (CON-006): the metamodel knows nothing about sorting. A preset is a list of
/// field names, the first is the main key. They match the Go dashboard's `sortPresets`.
enum SortPresets {
    static let byType: [String: [[String]]] = [
        "functional-requirement": [["priority", "release", "order"]],
        "issue": [["status", "severity"]],
        "decision-record": [["decided"]],
        "domain-term": [["title"]],
        "stakeholder": [["influence", "interest"]],
        "quality-requirement": [["priority"]],
    ]
}

extension Metamodel {
    /// The sort presets of a type, the first one is the default. Empty for a type without presets.
    public func sortPresets(for type: String) -> [[String]] {
        SortPresets.byType[type] ?? []
    }
}
