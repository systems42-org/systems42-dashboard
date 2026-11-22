import Foundation

/// The backlog: a ranked, linear reading of the requirements (`proj-backlog-ranking`). The Go
/// dashboard has no such view. The order is the brief's: priority, then release, then `order`, then id.
struct BacklogProjection {
    let model: ProjectionModel

    /// Priorities in the order the metamodel lists them for the `priority` field of a requirement,
    /// lower-cased. A priority the field does not list ranks after all that it lists.
    var priorityRanks: [String: Int] {
        let values = model.metamodel.type(named: FR.requirementType)?.fields
            .first { $0.name == FR.priorityField }?.values ?? []
        return Dictionary(values.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    func ranked() -> [Page] {
        let ranks = priorityRanks
        let pages = model.pages(ofType: FR.requirementType).filter { $0.status != FR.deprecatedStatus }
        func key(_ page: Page) -> (priority: Int, release: String, order: Int, id: String) {
            let release = page.trimmed(FR.releaseField)
            return (ranks[page.lowered(FR.priorityField)] ?? ranks.count,
                    release.isEmpty ? FR.unscheduled : release, page.order(field: FR.orderField), page.id)
        }
        // Releases: scheduled ones by name, `unscheduled` last.
        func releaseLess(_ a: String, _ b: String) -> Bool {
            if (a == FR.unscheduled) != (b == FR.unscheduled) { return b == FR.unscheduled }
            return Common.less(a, b)
        }
        return pages.enumerated().map { ($0.offset, $0.element, key($0.element)) }.sorted { a, b in
            if a.2.priority != b.2.priority { return a.2.priority < b.2.priority }
            if a.2.release != b.2.release { return releaseLess(a.2.release, b.2.release) }
            if a.2.order != b.2.order { return a.2.order < b.2.order }
            if a.2.id != b.2.id { return Common.less(a.2.id, b.2.id) }
            return a.0 < b.0
        }.map(\.1)
    }
}
