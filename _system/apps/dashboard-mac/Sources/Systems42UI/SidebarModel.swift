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
    /// Whether the maturity bar means anything: the section's lifecycle has an agreed status.
    public let showsMaturity: Bool
    public var id: String { section.id }
}

/// What the sidebar shows for one section, counted over all its pages.
struct SectionFigures: Sendable {
    /// Page counts per status, in the order the statuses first appear.
    private(set) var byStatus: [(status: String, count: Int)] = []
    /// The ids of the open issues that point at a page of the section, each issue once.
    var openIssueIDs = Set<String>()
    var openIssues: Int { openIssueIDs.count }

    var count: Int { byStatus.reduce(0) { $0 + $1.count } }
    var agreed: Int { byStatus.first { $0.status == Metamodel.agreedStatus }?.count ?? 0 }

    /// Page counts per status of the pages that "agreed only" keeps.
    private var kept: [String: Int] = [:]

    /// The counts of `ordered` as "agreed only" shows them: pages of a lifecycle without an agreed status stay.
    func keptByAgreedOnly(in ordered: [(status: String, count: Int)]) -> [(status: String, count: Int)] {
        ordered.compactMap { entry in kept[entry.status].flatMap { $0 > 0 ? (status: entry.status, count: $0) : nil } }
    }

    mutating func add(status: String, keptByAgreedOnly: Bool) {
        if keptByAgreedOnly { kept[status, default: 0] += 1 }
        if let at = byStatus.firstIndex(where: { $0.status == status }) {
            byStatus[at].count += 1
        } else {
            byStatus.append((status: status, count: 1))
        }
    }

    /// The counts in the order of `lifecycle`. Statuses it does not list, or all of them
    /// when it is nil, keep the order they first appear in.
    func ordered(by lifecycle: [String]?) -> [(status: String, count: Int)] {
        guard let lifecycle else { return byStatus }
        let rank = { (status: String) in lifecycle.firstIndex(of: status) ?? lifecycle.count }
        return byStatus.enumerated()
            .sorted { (rank($0.element.status), $0.offset) < (rank($1.element.status), $1.offset) }
            .map(\.element)
    }
}

/// The vision of the wiki and where it comes from, for the page column without a page.
public struct Orientation: Equatable, Sendable {
    public let title: String
    public let text: String
}
