import Foundation

/// Patton's story map over the hierarchy (`proj-story-map`): the backbone left to right, the ribs below
/// each backbone item by priority, the releases top to bottom. The Go dashboard has no such view.
public struct StoryMap: Sendable {
    /// The epics in `order`, then the use cases that Agile features or stories refine.
    public let backbone: [TreeNode]
    /// The releases that at least one card is in, in the order of the backlog: by name, numbers by
    /// value, `unscheduled` last. An epic that names a release and has no card in it adds no row.
    public let releases: [String]

    private let ranks: [String: Int]

    /// The features and stories below one backbone item (by page id) that belong to one release,
    /// by priority, then `order`, then id.
    public func cards(under: String, release: String) -> [TreeNode] {
        guard let root = backbone.first(where: { $0.id == under }) else { return [] }
        return StoryMap.descendants(of: root).filter { StoryMap.release(of: $0) == release }.sorted { a, b in
            let ra = ranks[a.priority.lowercased()] ?? ranks.count, rb = ranks[b.priority.lowercased()] ?? ranks.count
            if ra != rb { return ra < rb }
            if a.order != b.order { return a.order < b.order }
            return Common.less(a.id, b.id)
        }
    }

    /// The release of a page. A page with none is `unscheduled`.
    static func release(of node: TreeNode) -> String {
        node.release.isEmpty ? FR.unscheduled : node.release
    }

    /// The pages below a node in tree order, without the node.
    private static func descendants(of root: TreeNode) -> [TreeNode] {
        var found: [TreeNode] = []
        var stack = Array(root.children.reversed())
        while let node = stack.popLast() {
            found.append(node)
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }

    init(backbone: [TreeNode], priorityRanks: [String: Int]) {
        self.backbone = backbone
        ranks = priorityRanks
        let all = Set(backbone.flatMap(StoryMap.descendants(of:)).map(StoryMap.release(of:)))
        releases = all.sorted(by: FR.releaseLess)
    }
}

/// The goal and epic map of the functional-requirements page. Port of `MermaidGoalEpicTree`.
extension GoalsProjection {
    func goalEpicDiagram(links style: LinkStyle) -> String? {
        let hierarchy = FR.hierarchy(model.pages(ofType: FR.requirementType), model: model)
        let data = load()
        let hasUseCase = data.coverage.values.contains { $0.contains { FR.notation($0) == FR.useCase } }
        if hierarchy.epics.isEmpty && !hasUseCase { return nil }
        let epicByRef = Dictionary(hierarchy.epics.map { ($0.page.ref, $0) }, uniquingKeysWith: { _, last in last })

        var lines = ["graph TD"]
        var ids = NodeIDs(reserved: [Self.enablerID, Self.noGoalID])
        var seen = Set<PageRef>()

        func epicEdge(_ parent: String, _ epic: FRRow) {
            let nid = ids.id(of: epic.page)
            if seen.contains(epic.page.ref) {
                lines.append("  \(parent) --> \(nid)")
                return
            }
            let label = Common.cleanLabel(epic.page.title, dropParenthetical: true)
            lines.append("  \(parent) --> \(nid)[\"\(Common.label(epic.page.id))<br/>\(label)\"]:::\(Self.epicClass)")
            lines.append("  click \(nid) \"\(model.link(to: epic.page, style: style))\"")
            seen.insert(epic.page.ref)
        }
        func useCaseEdge(_ parent: String, _ useCase: Page) {
            let nid = ids.id(of: useCase)
            if seen.contains(useCase.ref) {
                lines.append("  \(parent) --> \(nid)")
                return
            }
            let label = Common.cleanLabel(useCase.title, dropParenthetical: true)
            lines.append("  \(parent) --> \(nid)[\"\(Common.label(useCase.id))<br/>\(label)\"]:::\(Self.useCaseClass)")
            lines.append("  click \(nid) \"\(model.link(to: useCase, style: style))\"")
            seen.insert(useCase.ref)
        }

        for objective in data.objectives {
            let gid = ids.id(of: objective)
            let label = Common.cleanLabel(shortTitle(objective), dropParenthetical: true)
            lines.append("  \(gid)[\"\(Common.label(objective.id))<br/>\(label)\"]:::\(Self.goalClass)")
            lines.append("  click \(gid) \"\(model.link(to: objective, style: style))\"")
            for requirement in data.coverage[objective.id] ?? [] {
                if FR.notation(requirement) == FR.useCase {
                    useCaseEdge(gid, requirement)
                    continue
                }
                if let epic = epicByRef[requirement.ref] { epicEdge(gid, epic) }
            }
        }

        let enablerEpics = data.enablers.compactMap { epicByRef[$0.ref] }
        if !enablerEpics.isEmpty {
            lines.append("  \(Self.enablerID)[\"\(Self.enablerLabel)\"]:::\(Self.enablerClass)")
            for epic in enablerEpics { epicEdge(Self.enablerID, epic) }
        }
        let untracedEpics = data.untraced.compactMap { page in epicByRef[page.ref].flatMap { seen.contains(page.ref) ? nil : $0 } }
        if !untracedEpics.isEmpty {
            lines.append("  \(Self.noGoalID)[\"\(Self.noGoalLabel)\"]:::\(Self.noGoalClass)")
            for epic in untracedEpics { epicEdge(Self.noGoalID, epic) }
        }

        lines += [
            "  classDef \(Self.goalClass) fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
            "  classDef \(Self.enablerClass) fill:#3a3f4b,stroke:#7a8497,color:#ffffff,font-weight:bold;",
            "  classDef \(Self.epicClass) fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
            "  classDef \(Self.useCaseClass) fill:#eef1f6,stroke:#9aa3b2,color:#15202e,stroke-dasharray:4 3;",
            "  classDef \(Self.noGoalClass) fill:#5a3d0c,stroke:#ffb454,color:#ffffff,stroke-width:2px,font-weight:bold;",
        ]
        return lines.joined(separator: "\n")
    }
}
