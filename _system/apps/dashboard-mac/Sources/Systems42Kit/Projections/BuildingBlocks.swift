import Foundation

/// The building block view (arc42 section 5): the level tree and the white box diagram.
/// Port of `BuildBBTree` and `BuildWhitebox` in `internal/project/arch.go`.
struct BuildingBlocksProjection {
    let model: ProjectionModel

    /// The projection pages this reads. Go: arch.go `BuildBBTree` and `BuildWhitebox`.
    static let treeProjection = "bb-tree", whiteboxProjection = "whitebox"
    static let treeDeclaration = ProjectionDeclaration(treeProjection, [(Arch.blockType, [Arch.parentRelation, Arch.usesRelation])])
    static let whiteboxDeclaration = ProjectionDeclaration(whiteboxProjection, [
        (Arch.blockType, [Arch.parentRelation, Arch.usesRelation, Arch.stateField, Arch.supersededByRelation]),
        (Arch.interfaceType, []),
    ])

    /// Go: arch.go `BuildWhitebox`, `eifByStem`, the classes in the last lines.
    private static let classes = [
        "  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
        "  classDef outside fill:#e3ecf7,stroke:#2f6fb3,stroke-dasharray:4 3,color:#15202e;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]

    func tree() -> [LevelNode] {
        model.levelTree(model.pages(ofType: Arch.blockType))
    }

    /// Ports `BuildWhitebox`: the children of `stem` ("" for level 1) with their `uses:` edges.
    /// Nil when there are no children.
    func whitebox(of stem: String, links style: LinkStyle = .dashboard) -> String? {
        let tree = tree()
        let kids: [LevelNode]
        if stem.isEmpty {
            kids = tree
        } else {
            kids = treeFind(tree, stem: stem)?.children ?? []
        }
        if kids.isEmpty { return nil }

        let inside = Set(kids.map(\.page.stem))
        var blockByStem: [String: Page] = [:]
        for page in model.pages(ofType: Arch.blockType) { blockByStem[page.stem] = page }
        var interfaceByStem: [String: Page] = [:]
        for page in model.pages(ofType: Arch.interfaceType) { interfaceByStem[page.stem] = page }

        let mixed = isMixedLifecycle(kids.map(\.page))
        var ids = NodeIDs()
        var lines = ["flowchart LR"]
        for kid in kids {
            let page = kid.page
            let suffix = model.lifecycleSuffix(page, mixed: mixed)
            lines.append("  \(ids.id(of: page))[\"\(Common.label(page.id)) · \(Common.cleanLabel(page.title, dropParenthetical: true))\(suffix)\"]:::block")
        }

        var neighbours: [String] = [], neighbourSet = Set<String>()
        var outside: [String] = [], outsideSet = Set<String>()
        var edges: [String] = []
        for kid in kids {
            let source = ids.id(of: kid.page)
            for target in model.linkedStems(kid.page, relation: Arch.usesRelation) {
                if inside.contains(target), let block = blockByStem[target] {
                    edges.append("  \(source) --> \(ids.id(of: block))")
                } else if let block = blockByStem[target] {
                    if outsideSet.insert(target).inserted { outside.append(target) }
                    edges.append("  \(source) --> \(ids.id(of: block))")
                } else if let interface = interfaceByStem[target] {
                    if neighbourSet.insert(target).inserted { neighbours.append(target) }
                    edges.append("  \(source) --> \(ids.id(of: interface))")
                }
            }
        }

        for stem in outside {
            guard let block = blockByStem[stem] else { continue }
            let suffix = model.lifecycleSuffix(block, mixed: mixed)
            lines.append("  \(ids.id(of: block))[\"\(Common.label(block.id)) · \(Common.cleanLabel(block.title, dropParenthetical: true))\(suffix)\"]:::outside")
        }
        for stem in neighbours {
            guard let interface = interfaceByStem[stem] else { continue }
            lines.append("  \(ids.id(of: interface))[\"\(Common.cleanLabel(interface.title, dropParenthetical: true))\"]:::system")
        }
        lines += edges
        // The Go dashboard draws no click here. The app does: every node of a page is clickable.
        if style == .page {
            for kid in kids { lines.append("  click \(ids.id(of: kid.page)) \"\(model.link(to: kid.page, style: style))\"") }
            for stem in outside { if let block = blockByStem[stem] { lines.append("  click \(ids.id(of: block)) \"\(model.link(to: block, style: style))\"") } }
            for stem in neighbours { if let page = interfaceByStem[stem] { lines.append("  click \(ids.id(of: page)) \"\(model.link(to: page, style: style))\"") } }
        }

        var marked: [MarkedEntry] = []
        for stem in kids.map(\.page.stem) + outside {
            if let block = blockByStem[stem] {
                marked.append(MarkedEntry(key: stem, nid: ids.id(of: block), page: block))
            }
        }
        lines += model.lifecycleLines(marked)
        lines += Self.classes
        return lines.joined(separator: "\n")
    }
}
