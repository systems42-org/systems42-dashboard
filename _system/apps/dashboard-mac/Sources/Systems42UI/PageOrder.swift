import Foundation
import Systems42Kit

/// The keys every page has, whatever its type (AGENTS.md: universal frontmatter). Everything else
/// a list sorts or filters by comes from the metamodel (CON-006).
enum UniversalField {
    static let id = "id", title = "title", status = "status"
}

/// Sorts and filters pages. Pure, so it can be tested without a window.
struct PageOrder: Sendable {
    /// Declared values in order, per field. Status holds the lifecycle.
    private let ranks: [String: [String: Int]]

    /// `enums`: the declared values of each enum field. `statuses`: the lifecycle, nil when there is none.
    init(enums: [String: [String]], statuses: [String]?) {
        var all = enums
        if let statuses { all[UniversalField.status] = statuses }
        ranks = all.mapValues { values in
            Dictionary(values.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// What a page holds in a field, as text. A list is joined by commas. Empty when it holds nothing.
    static func values(of field: String, in page: Page) -> [String] {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch page.fields[field] {
        case .text(let text)?: return [trimmed(text)].filter { !$0.isEmpty }
        case .list(let items)?: return items.map(trimmed).filter { !$0.isEmpty }
        case .links(let links)?: return links.map(\.name)
        case .other?: return []
        case nil:
            // `id` and `title` fall back to the file name in `Page`.
            switch field {
            case UniversalField.id: return [page.id]
            case UniversalField.title: return [page.title]
            case UniversalField.status: return page.status.isEmpty ? [] : [page.status]
            default: return []
            }
        }
    }

    static func text(of field: String, in page: Page) -> String {
        values(of: field, in: page).joined(separator: ", ")
    }

    /// Keeps the pages that pass `agreedOnly` and all `filters`, then orders them by `sort`.
    /// Pages that tie end in id order, `FR-2` before `FR-10`.
    func arrange(_ pages: [Page], sort: [SortKey], filters: [String: Set<String>], agreedOnly: Bool) -> [Page] {
        let wanted = filters.compactMapValues { $0.isEmpty ? nil : Set($0.map { $0.lowercased() }) }
        let kept = pages.filter { page in
            if agreedOnly, page.status.lowercased() != agreedStatus { return false }
            return wanted.allSatisfy { field, accepted in
                Self.values(of: field, in: page).contains { accepted.contains($0.lowercased()) }
            }
        }
        guard !sort.isEmpty else { return kept.sorted { Self.idBefore($0, $1) } }
        let rows = kept.map { page in Row(page: page, cells: sort.map { cell(for: $0.field, in: page) }) }
        return rows.sorted { a, b in
            for (at, key) in sort.enumerated() {
                switch (a.cells[at], b.cells[at]) {
                case (nil, nil): continue
                // A missing value is no small value: last in both directions.
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?):
                    var order = x.rank < y.rank ? ComparisonResult.orderedAscending : x.rank > y.rank ? .orderedDescending : Self.compare(x.text, y.text)
                    if !key.ascending { order = order == .orderedAscending ? .orderedDescending : order == .orderedDescending ? .orderedAscending : order }
                    if order != .orderedSame { return order == .orderedAscending }
                }
            }
            return Self.idBefore(a.page, b.page)
        }.map(\.page)
    }

    private struct Row {
        let page: Page
        let cells: [Cell?]
    }

    /// The sort value of one field. Declared enum values rank by their position, others rank after them.
    private struct Cell {
        let rank: Int
        let text: String
    }

    private func cell(for field: String, in page: Page) -> Cell? {
        let text = Self.text(of: field, in: page)
        if text.isEmpty { return nil }
        guard let declared = ranks[field] else { return Cell(rank: 0, text: text) }
        return Cell(rank: declared[text.lowercased()] ?? declared.count, text: text)
    }

    private static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.numeric, .caseInsensitive])
    }

    private static func idBefore(_ a: Page, _ b: Page) -> Bool {
        let order = compare(a.id, b.id)
        return order == .orderedSame ? a.ref.stem < b.ref.stem : order == .orderedAscending
    }
}
