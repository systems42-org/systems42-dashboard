import Systems42Kit

/// SwiftUI also has a `Section`, so views say `WikiSection`.
public typealias WikiSection = Section

/// One area of the sidebar with its sections in metamodel order.
public struct SidebarGroup: Identifiable {
    public let area: Area
    public let rows: [SidebarRow]
    public var id: Area { area }
}

/// One section of the sidebar.
public struct SidebarRow: Identifiable {
    public let section: WikiSection
    /// The pages of the section, or only its agreed pages while `agreedOnly` is on.
    public let count: Int
    /// Page counts per status in lifecycle order, statuses without pages left out.
    public let byStatus: [(status: String, count: Int)]
    /// Open issues that point at a page of the section, each issue counted once.
    public let openIssues: Int
    /// The share of agreed pages among all pages of the section, 0 for an empty section.
    public let agreedShare: Double
    public var id: String { section.id }
}

/// The status that counts as agreed, and the order statuses are listed in.
/// The metamodel names the lifecycle in prose only, so it is fixed here (open debt).
enum Lifecycle {
    static let agreed = "accepted"
    static let order = ["draft", "review", agreed, "deprecated"]

    static func sorted(_ counts: [String: Int]) -> [(status: String, count: Int)] {
        counts.sorted { a, b in
            let ra = order.firstIndex(of: a.key) ?? order.count, rb = order.firstIndex(of: b.key) ?? order.count
            return (ra, a.key) < (rb, b.key)
        }.map { (status: $0.key, count: $0.value) }
    }
}

/// What the sidebar shows for one section, counted over all its pages.
struct SectionFigures: Sendable {
    var byStatus: [String: Int] = [:]
    var openIssues = 0

    var count: Int { byStatus.values.reduce(0, +) }
    var agreed: Int { byStatus[Lifecycle.agreed] ?? 0 }
}

/// The vision of the wiki and where it comes from, for the page column without a page.
public struct Orientation: Equatable, Sendable {
    public let title: String
    public let text: String
}
