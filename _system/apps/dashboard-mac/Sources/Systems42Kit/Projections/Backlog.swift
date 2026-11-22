import Foundation

/// The backlog: a ranked, linear reading of the requirements (`proj-backlog-ranking`). The Go
/// dashboard has no such view.
struct BacklogProjection {
    let model: ProjectionModel

    static let projection = "backlog-ranking"
    static let declaration = ProjectionDeclaration(projection, [
        (FR.requirementType, [FR.priorityField, FR.releaseField, FR.orderField]),
    ])

    /// By release, then priority, then `order`, then id (`proj-backlog-ranking`). Releases go by
    /// `FR.releaseLess`. Deprecated requirements are left out.
    func ranked() -> [Page] {
        let ranks = FR.priorityRanks(model)
        let pages = model.pages(ofType: FR.requirementType).filter { $0.status != FR.deprecatedStatus }
        func key(_ page: Page) -> (release: String, priority: Int, order: Int, id: String) {
            let release = page.trimmed(FR.releaseField)
            return (release.isEmpty ? FR.unscheduled : release, ranks[page.lowered(FR.priorityField)] ?? ranks.count,
                    page.order(field: FR.orderField), page.id)
        }
        return pages.enumerated().map { ($0.offset, $0.element, key($0.element)) }.sorted { a, b in
            if a.2.release != b.2.release { return FR.releaseLess(a.2.release, b.2.release) }
            if a.2.priority != b.2.priority { return a.2.priority < b.2.priority }
            if a.2.order != b.2.order { return a.2.order < b.2.order }
            if a.2.id != b.2.id { return Common.less(a.2.id, b.2.id) }
            return a.0 < b.0
        }.map(\.1)
    }
}
