import Foundation

/// One requirement in the hierarchy: its page, and the pages that name it in `parent:` below it.
public struct TreeNode: Identifiable, Sendable {
    public let id: String
    public let ref: PageRef?
    public let title, level, status: String
    public let priority, release: String
    /// The `order` field, 9999 when the page has none.
    public let order: Int
    public let children: [TreeNode]

    init(_ page: Page, children: [TreeNode] = []) {
        id = page.id
        ref = page.ref
        title = page.title
        level = FR.level(page)
        status = page.status
        priority = page.trimmed(FR.priorityField)
        release = page.trimmed(FR.releaseField)
        order = page.order(field: FR.orderField)
        self.children = children
    }
}

/// The requirement hierarchy and the detail of one requirement. Ports `BuildFRHierarchy`,
/// `FRBuildingBlocks` and `MermaidFRSubtree` of `internal/project/goals_fr.go`.
struct HierarchyProjection {
    let model: ProjectionModel

    /// The projection page this reads. Go: goals_fr.go `BuildFRHierarchy`, the story map of DR-038.
    static let projection = "story-map"
    static let declaration = ProjectionDeclaration(projection, [
        (FR.requirementType, [FR.notationField, FR.levelField, FR.parentRelation, FR.orderField, FR.priorityField, FR.releaseField]),
        (FR.blockType, [FR.driversRelation]),
    ])
    /// Mermaid class names of the diagram. Go: `MermaidFRSubtree`.
    static let rootClass = "root", featureClass = "feature", storyClass = "story", blockClass = "block"

    /// The nodes of the Go hierarchy: epics, then use cases that have children, with features and
    /// stories below. Then the pages the Go lists keep apart (orphans, other notations) and the agile pages
    /// whose parent chain reaches no epic or use case (a cycle, a story under a story), so every
    /// non-deprecated requirement appears exactly once.
    func roots() -> [TreeNode] {
        let (backbone, others) = split()
        return backbone + others
    }

    /// The backbone (epics, then use cases with children) and the other roots.
    func split() -> (backbone: [TreeNode], others: [TreeNode]) {
        let hierarchy = FR.hierarchy(model.pages(ofType: FR.requirementType), model: model)
        func node(_ row: FRRow) -> TreeNode {
            TreeNode(row.page, children: (row.features.isEmpty ? [] : row.features.map(node))
                + row.directStories.map(node) + row.stories.map(node))
        }
        let backbone = hierarchy.epics.map(node) + hierarchy.useCases.map(node)
        var roots: [TreeNode] = []
        var placed = Set<PageRef>()
        func collect(_ row: FRRow) {
            placed.insert(row.page.ref)
            (row.features + row.directStories + row.stories).forEach(collect)
        }
        (hierarchy.epics + hierarchy.useCases).forEach(collect)
        for row in hierarchy.orphans + hierarchy.otherNotations where placed.insert(row.page.ref).inserted {
            roots.append(TreeNode(row.page))
        }
        let rest = model.pages(ofType: FR.requirementType)
            .filter { $0.status != FR.deprecatedStatus && !placed.contains($0.ref) }
        roots += ProjectionModel.sortedByID(rest).map { TreeNode($0) }
        return (backbone, roots)
    }

    /// The pages that name the page in `parent:`, and the building blocks that name it in `drivers:`.
    func detail(of id: String) -> (children: [Page], buildingBlocks: [Page]) {
        guard let page = model.all.first(where: { $0.id == id }) ?? model.byStem[id] else { return ([], []) }
        let field = model.field(ofRelation: FR.parentRelation)
        let children = model.all.filter { child in
            child.ref != page.ref && child.links(field, existing: { model.byStem[$0] != nil }).contains(page.stem)
        }
        return (ProjectionModel.sortedByID(children), FR.buildingBlocks(of: page.stem, model: model))
    }

    /// Ports `MermaidFRSubtree` and the setup of `handleFRDetail`: one requirement's own feature and story
    /// breakdown plus the building blocks that name it in `drivers:`.
    func subtreeDiagram(of page: Page, links style: LinkStyle) -> String? {
        let hierarchy = FR.hierarchy(model.pages(ofType: FR.requirementType), model: model)
        let node = FR.node(hierarchy, stem: page.stem)?.row
        let blocks = FR.buildingBlocks(of: page.stem, model: model)
        let features = node?.features ?? []
        let ownStories = node?.stories ?? []
        let direct = node?.directStories ?? []
        if features.isEmpty && ownStories.isEmpty && direct.isEmpty && blocks.isEmpty { return nil }

        var ids = NodeIDs()
        let rootID = ids.id(of: page)
        var lines = [
            "graph TD",
            "  \(rootID)[\"\(Common.label(page.id))<br/>\(Common.cleanLabel(page.title, dropParenthetical: true))\"]:::\(Self.rootClass)",
        ]
        func child(_ parent: String, _ row: FRRow, _ css: String) -> String {
            let nid = ids.id(of: row.page)
            let label = Common.cleanLabel(row.page.title, dropParenthetical: true)
            lines.append("  \(parent) --> \(nid)[\"\(Common.label(row.page.id))<br/>\(label)\"]:::\(css)")
            lines.append("  click \(nid) \"\(model.link(to: row.page, style: style))\"")
            return nid
        }
        for feature in features {
            let featureID = child(rootID, feature, Self.featureClass)
            for story in feature.stories { _ = child(featureID, story, Self.storyClass) }
        }
        for story in ownStories { _ = child(rootID, story, Self.storyClass) }
        for story in direct { _ = child(rootID, story, Self.storyClass) }
        for block in blocks {
            let nid = ids.id(of: block)
            lines.append("  \(rootID) -.-> \(nid)[[\"\(Common.label(block.id))<br/>\(Common.cleanLabel(block.title, dropParenthetical: true))\"]]:::\(Self.blockClass)")
            lines.append("  click \(nid) \"\(model.link(to: block, style: style))\"")
        }
        // The Go dashboard draws no click on the root, the page you are on. The app does.
        if style == .page { lines.append("  click \(rootID) \"\(model.link(to: page, style: style))\"") }
        lines += [
            "  classDef \(Self.rootClass) fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
            "  classDef \(Self.featureClass) fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
            "  classDef \(Self.storyClass) fill:#f3f6fb,stroke:#c4ccd9,color:#15202e;",
            "  classDef \(Self.blockClass) fill:#e3efe6,stroke:#6f9b7c,color:#15202e;",
        ]
        return lines.joined(separator: "\n")
    }
}
