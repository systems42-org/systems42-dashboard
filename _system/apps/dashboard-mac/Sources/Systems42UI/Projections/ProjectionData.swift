import Foundation
import Systems42Kit

/// The names of the requirement fields the UI reads next to the Kit's projections.
/// Open debt (CON-006): the metamodel declares these fields but does not mark them by role.
enum ProjectionFields {
    static let priority = "priority", release = "release", level = "level"
}

/// A page as a card, a row or a header shows it.
struct ProjectionItem: Sendable, Hashable {
    let ref: PageRef?
    let id, title, status: String

    init(_ page: Page) {
        ref = page.ref
        id = page.id
        title = page.title
        status = page.status
    }

    init(_ node: TreeNode) {
        ref = node.ref
        id = node.id
        title = node.title
        status = node.status
    }

    /// The id and the title, the words a link or a spoken label uses.
    var text: String { title.isEmpty ? id : "\(id) \(title)" }

    /// A key made of the page reference, for `ForEach`. Never the page id: a wiki does not keep ids unique.
    var key: String { ref.map { "\($0.folder)/\($0.stem)" } ?? "" }
}

// MARK: Story map

/// The story map as the view draws it: backbone columns, release rows, cards in the cells.
struct StoryMapModel: Sendable {
    struct Card: Sendable {
        let item: ProjectionItem
        let level, priority: String
        /// What a screen reader says.
        var accessibilityLabel: String {
            [item.text, level, item.status, priority.isEmpty ? "" : "priority \(priority)"].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    struct Column: Sendable {
        let item: ProjectionItem
        let level: String
        /// The cards by release.
        let cards: [String: [Card]]

        var accessibilityLabel: String {
            [item.text, level, item.status].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    let columns: [Column]
    /// The releases with at least one card, in backlog order.
    let releases: [String]

    var isEmpty: Bool { columns.isEmpty }

    func cards(column: Int, release: String) -> [Card] {
        columns.indices.contains(column) ? columns[column].cards[release] ?? [] : []
    }

    /// The ids of the backbone items and the cards: every requirement of the map once.
    var allIDs: [String] {
        columns.flatMap { column in [column.item.id] + column.cards.values.flatMap { $0.map(\.item.id) } }
    }

    init(_ map: StoryMap) {
        releases = map.releases
        columns = map.backbone.map { node in
            var byRelease: [String: [Card]] = [:]
            for release in map.releases {
                let cards = map.cards(under: node.id, release: release).map {
                    Card(item: ProjectionItem($0), level: $0.level, priority: $0.priority)
                }
                if !cards.isEmpty { byRelease[release] = cards }
            }
            return Column(item: ProjectionItem(node), level: node.level, cards: byRelease)
        }
    }
}

// MARK: Hierarchy

/// One node of the outline. The key is its place in the tree, so it is unique whatever the page ids are.
struct OutlineNode: Sendable {
    let key: String
    let item: ProjectionItem
    let level: String
    let children: [OutlineNode]

    struct Row: Sendable {
        let node: OutlineNode
        let depth: Int
        let expanded: Bool
        var hasChildren: Bool { !node.children.isEmpty }
    }

    var allIDs: [String] { [item.id] + children.flatMap(\.allIDs) }

    init(_ node: TreeNode, key: String) {
        self.key = key
        item = ProjectionItem(node)
        level = node.level
        children = node.children.enumerated().map { OutlineNode($1, key: "\(key).\($0)") }
    }

    static func roots(_ nodes: [TreeNode]) -> [OutlineNode] {
        nodes.enumerated().map { OutlineNode($1, key: "\($0)") }
    }

    /// The rows that are visible when the nodes whose key is in `collapsed` hide their children.
    static func flatten(_ roots: [OutlineNode], collapsed: Set<String>) -> [Row] {
        var rows: [Row] = []
        var stack = roots.reversed().map { (node: $0, depth: 0) }
        while let (node, depth) = stack.popLast() {
            let open = !collapsed.contains(node.key)
            rows.append(Row(node: node, depth: depth, expanded: open))
            if open { stack.append(contentsOf: node.children.reversed().map { (node: $0, depth: depth + 1) }) }
        }
        return rows
    }
}

/// What the detail of one requirement shows: the pages that name it as parent, and its building blocks.
struct HierarchyDetail: Sendable {
    let children: [ProjectionItem]
    let buildingBlocks: [ProjectionItem]
    var isEmpty: Bool { children.isEmpty && buildingBlocks.isEmpty }
}

// MARK: Goal matrix

/// The goal coverage matrix as the view draws it.
struct MatrixModel: Sendable {
    struct Column: Sendable {
        let item: ProjectionItem
        let level: String
        let enabler, untraced: Bool

        /// Gap and untraced states are words, not colour (FR-036).
        var accessibilityLabel: String {
            var parts = [item.text, level, item.status].filter { !$0.isEmpty }
            if untraced { parts.append("names no goal, breaks the rule that every epic names a goal") }
            if enabler { parts.append("enabler") }
            return parts.joined(separator: ", ")
        }
    }

    struct Row: Sendable {
        let item: ProjectionItem
        /// No requirement serves the goal.
        let gap: Bool
        /// Requirements serve the goal but none is agreed.
        let acceptedGap: Bool
        /// One entry per column.
        let marks: [Bool]
        /// Every requirement that serves the goal, as text under the matrix.
        let serving: [ProjectionItem]

        var accessibilityLabel: String {
            var parts = [item.text, item.status].filter { !$0.isEmpty }
            if gap { parts.append("no requirement serves this goal") }
            else if acceptedGap { parts.append("no agreed requirement serves this goal") }
            else { parts.append("served by \(serving.count)") }
            return parts.joined(separator: ", ")
        }
    }

    let columns: [Column]
    let rows: [Row]

    var isEmpty: Bool { rows.isEmpty && columns.isEmpty }

    /// Where the enabler columns start, nil when there are none.
    var enablerStart: Int? { columns.firstIndex { $0.enabler } }

    func cellLabel(row: Row, column: Int) -> String {
        guard columns.indices.contains(column), row.marks.indices.contains(column) else { return "" }
        let other = columns[column].item
        return row.marks[column] ? "\(other.id) serves \(row.item.id)" : "\(other.id) does not serve \(row.item.id)"
    }

    init(_ matrix: GoalMatrix) {
        let enablerIDs = Set(matrix.enablers.map(\.id))
        columns = matrix.columns.map {
            Column(item: ProjectionItem($0), level: PageOrder.text(of: ProjectionFields.level, in: $0),
                   enabler: enablerIDs.contains($0.id), untraced: matrix.untraced.contains($0.id))
        }
        rows = matrix.goals.map { goal in
            Row(item: ProjectionItem(goal), gap: matrix.gaps.contains(goal.id), acceptedGap: matrix.acceptedGaps.contains(goal.id),
                marks: matrix.columns.map { matrix.marked(goal: goal.id, column: $0.id) },
                serving: matrix.servedBy(goal: goal.id).map(ProjectionItem.init))
        }
    }
}

// MARK: Backlog

struct BacklogRow: Sendable {
    let rank: Int
    let item: ProjectionItem
    let release, priority, level: String

    var accessibilityLabel: String {
        ["rank \(rank)", item.text, level, item.status, release.isEmpty ? "" : "release \(release)", priority.isEmpty ? "" : "priority \(priority)"]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: All of it

/// The four projections of one revision of the wiki and one setting of "agreed only", computed off the main thread.
struct ProjectionData: Sendable {
    let revision: Int
    let agreedOnly: Bool
    let storyMap: StoryMapModel
    let outline: [OutlineNode]
    let matrix: MatrixModel
    let backlog: [BacklogRow]
    /// The snapshot the models came from, for the detail of one requirement.
    let projections: Projections

    static func build(store: WikiStore, metamodel: Metamodel, agreedOnly: Bool, revision: Int) -> ProjectionData {
        let projections = Projections(store: store, metamodel: metamodel, agreedOnly: agreedOnly)
        let backlog = projections.backlog().enumerated().map { offset, page in
            BacklogRow(rank: offset + 1, item: ProjectionItem(page),
                       release: PageOrder.text(of: ProjectionFields.release, in: page),
                       priority: PageOrder.text(of: ProjectionFields.priority, in: page),
                       level: PageOrder.text(of: ProjectionFields.level, in: page))
        }
        return ProjectionData(
            revision: revision, agreedOnly: agreedOnly, storyMap: StoryMapModel(projections.storyMap()),
            outline: OutlineNode.roots(projections.hierarchy()), matrix: MatrixModel(projections.goalMatrix()),
            backlog: backlog, projections: projections
        )
    }
}

/// The line a projection shows when the wiki has nothing for it.
enum ProjectionHint {
    static func text(for mode: String) -> String {
        switch mode {
        case ProjectionHost.matrixMode: "No goals yet, so there is no matrix to show."
        case ProjectionHost.backlogMode: "No requirements yet, so there is no backlog."
        default: "No requirements yet, so there is no map to show."
        }
    }
}
