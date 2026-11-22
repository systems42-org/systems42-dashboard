import Foundation

/// Patton's story map over the hierarchy: the backbone left to right, the releases top to bottom.
/// The Go dashboard has no such view, `proj-story-map` declares it. Backbone and cards come from
/// `HierarchyProjection.roots()`.
public struct StoryMap: Sendable {
    /// The epics in `order`, then the use cases that Agile features or stories refine.
    public let backbone: [TreeNode]
    /// The releases the pages name, in the order they first appear in the backbone, `unscheduled` last.
    public let releases: [String]

    /// The features and stories below one backbone item (by page id) that belong to one release, in tree order.
    public func cards(under: String, release: String) -> [TreeNode] {
        guard let root = backbone.first(where: { $0.id == under }) else { return [] }
        var found: [TreeNode] = []
        var stack = Array(root.children.reversed())
        while let node = stack.popLast() {
            if StoryMap.release(of: node) == release { found.append(node) }
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }

    /// The release of a page. A page with none is `unscheduled`.
    static func release(of node: TreeNode) -> String {
        node.release.isEmpty ? FR.unscheduled : node.release
    }

    init(backbone: [TreeNode]) {
        self.backbone = backbone
        var seen = Set<String>()
        var order: [String] = []
        var stack = Array(backbone.reversed())
        while let node = stack.popLast() {
            let release = StoryMap.release(of: node)
            if seen.insert(release).inserted { order.append(release) }
            stack.append(contentsOf: node.children.reversed())
        }
        releases = order.filter { $0 != FR.unscheduled } + order.filter { $0 == FR.unscheduled }
    }
}

/// The goal and epic map of the functional-requirements page. Port of `MermaidGoalEpicTree`.
extension GoalsProjection {
    func goalEpicDiagram() -> String? {
        let hierarchy = FR.hierarchy(model.pages(ofType: FR.requirementType), model: model)
        let data = load()
        let hasUseCase = data.coverage.values.contains { $0.contains { FR.notation($0) == FR.useCase } }
        if hierarchy.epics.isEmpty && !hasUseCase { return nil }
        let epicByID = Dictionary(hierarchy.epics.map { ($0.page.id, $0) }, uniquingKeysWith: { _, last in last })

        var lines = ["graph TD"]
        var seen = Set<String>()

        func epicEdge(_ parent: String, _ epic: FRRow) {
            let id = epic.page.id
            let nid = Common.diagramNodeID(id)
            if seen.contains(id) {
                lines.append("  \(parent) --> \(nid)")
                return
            }
            let label = Common.cleanLabel(epic.page.title, dropParenthetical: true)
            lines.append("  \(parent) --> \(nid)[\"\(id)<br/>\(label)\"]:::epic")
            lines.append("  click \(nid) \"\(FR.requirementURL)\(epic.page.stem)\"")
            seen.insert(id)
        }
        func useCaseEdge(_ parent: String, _ useCase: Page) {
            let nid = Common.diagramNodeID(useCase.id)
            if seen.contains(useCase.id) {
                lines.append("  \(parent) --> \(nid)")
                return
            }
            let label = Common.cleanLabel(useCase.title, dropParenthetical: true)
            lines.append("  \(parent) --> \(nid)[\"\(useCase.id)<br/>\(label)\"]:::usecase")
            lines.append("  click \(nid) \"\(FR.url(of: useCase, model: model))\"")
            seen.insert(useCase.id)
        }

        for objective in data.objectives {
            let gid = Common.diagramNodeID(objective.id)
            let label = Common.cleanLabel(shortTitle(objective), dropParenthetical: true)
            lines.append("  \(gid)[\"\(objective.id)<br/>\(label)\"]:::goal")
            lines.append("  click \(gid) \"\(FR.goalURL)\(objective.id)\"")
            for requirement in data.coverage[objective.id] ?? [] {
                if FR.notation(requirement) == FR.useCase {
                    useCaseEdge(gid, requirement)
                    continue
                }
                if let epic = epicByID[requirement.id] { epicEdge(gid, epic) }
            }
        }

        let enablerEpics = data.enablers.compactMap { epicByID[$0.id] }
        if !enablerEpics.isEmpty {
            lines.append("  ENABLER[\"Platform / Enabler\"]:::enabler")
            for epic in enablerEpics { epicEdge("ENABLER", epic) }
        }
        let untracedEpics = data.untraced.compactMap { page in epicByID[page.id].flatMap { seen.contains(page.id) ? nil : $0 } }
        if !untracedEpics.isEmpty {
            lines.append("  NOGOAL[\"No goal\"]:::nogoal")
            for epic in untracedEpics { epicEdge("NOGOAL", epic) }
        }

        lines += [
            "  classDef goal fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
            "  classDef enabler fill:#3a3f4b,stroke:#7a8497,color:#ffffff,font-weight:bold;",
            "  classDef epic fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
            "  classDef usecase fill:#eef1f6,stroke:#9aa3b2,color:#15202e,stroke-dasharray:4 3;",
            "  classDef nogoal fill:#5a3d0c,stroke:#ffb454,color:#ffffff,stroke-width:2px,font-weight:bold;",
        ]
        return lines.joined(separator: "\n")
    }
}
