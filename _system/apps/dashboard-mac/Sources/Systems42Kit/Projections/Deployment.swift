import Foundation

/// The deployment view (arc42 section 7): nodes nested by `parent:`, the blocks they host, the
/// connections between them. Port of `BuildDeploymentDiagram` in `internal/project/arch.go`.
struct DeploymentProjection {
    let model: ProjectionModel

    /// Go: arch.go `BuildDeploymentDiagram`, the classes in the last lines.
    private static let classes = [
        "  classDef infra fill:#e3ecf7,stroke:#2f6fb3,color:#15202e;",
        "  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]

    func tree() -> [LevelNode] {
        model.levelTree(model.pages(ofType: Arch.nodeType))
    }

    /// The diagram of all nodes (`root` empty) or of the subtree under `root`. Nil when there is nothing to draw.
    func diagram(root: String = "") -> String? {
        var tree = tree()
        if !root.isEmpty {
            guard let me = treeFind(tree, stem: root) else { return nil }
            tree = [me]
        }
        if tree.isEmpty { return nil }

        let nodes = model.pages(ofType: Arch.nodeType)
        var nodeByStem: [String: Page] = [:]
        for page in nodes { nodeByStem[page.stem] = page }
        var blockByStem: [String: Page] = [:]
        for page in model.pages(ofType: Arch.blockType) { blockByStem[page.stem] = page }
        var interfaceByStem: [String: Page] = [:]
        for page in model.pages(ofType: Arch.interfaceType) { interfaceByStem[page.stem] = page }

        func hostedBlocks(_ node: Page) -> [String] {
            model.linkedStems(node, relation: Arch.hostsRelation).filter { blockByStem[$0] != nil }
        }

        var inside: [Page] = []
        var stack = Array(tree.reversed())
        while let node = stack.popLast() {
            inside.append(node.page)
            stack.append(contentsOf: node.children.reversed())
        }
        let nodeCount = inside.count
        for index in 0..<nodeCount {
            for stem in hostedBlocks(inside[index]) { inside.append(blockByStem[stem]!) }
        }
        let mixed = isMixedLifecycle(inside)

        var shown = Set<String>()
        var marked: [String: MarkedEntry] = [:]
        var lines = ["flowchart TB"]

        func emit(_ node: LevelNode, depth: Int) {
            let page = node.page
            let pad = String(repeating: "  ", count: depth)
            let nid = Common.diagramNodeID(page.id)
            var label = "\(page.id) · \(Common.cleanLabel(page.title, dropParenthetical: true))"
            let technology = Common.cleanLabel(page.text(Arch.technologyField), dropParenthetical: true)
            if !technology.isEmpty { label += " (\(technology))" }
            label += model.lifecycleSuffix(page, mixed: mixed)
            shown.insert(page.stem)
            marked[page.stem] = MarkedEntry(key: page.stem, nid: nid, page: page)

            let hosted = hostedBlocks(page)
            if node.children.isEmpty && hosted.isEmpty {
                lines.append("\(pad)\(nid)[\"\(label)\"]:::infra")
                return
            }
            lines.append("\(pad)subgraph \(nid)[\"\(label)\"]")
            for stem in hosted {
                let block = blockByStem[stem]!
                let blockID = "\(nid)_\(Common.diagramNodeID(block.id))"
                let key = page.stem + "/" + stem
                marked[key] = MarkedEntry(key: key, nid: blockID, page: block)
                lines.append("\(pad)  \(blockID)[\"\(block.id) · \(Common.cleanLabel(block.title, dropParenthetical: true))\(model.lifecycleSuffix(block, mixed: mixed))\"]:::block")
            }
            for child in node.children { emit(child, depth: depth + 1) }
            lines.append(pad + "end")
        }
        for node in tree { emit(node, depth: 1) }

        let shownSorted = ProjectionModel.sortedByID(shown.sorted().compactMap { nodeByStem[$0] })
        var neighbours: [String] = [], neighbourSet = Set<String>()
        var edges: [String] = []
        for node in shownSorted {
            for case .entry(let entry) in node.entries(model.field(ofRelation: Arch.connectsRelation)) {
                let to = entry[Arch.toKey] ?? ""
                let stem = to.isEmpty ? "" : Frontmatter.pageName(in: to)
                let target: String
                if shown.contains(stem), let page = nodeByStem[stem] {
                    target = Common.diagramNodeID(page.id)
                } else if let interface = interfaceByStem[stem] {
                    target = Common.diagramNodeID(interface.id)
                    if neighbourSet.insert(stem).inserted { neighbours.append(stem) }
                } else {
                    continue
                }
                var parts: [String] = []
                let protocolText = Common.edgeText(entry[Arch.protocolKey] ?? "")
                if !protocolText.isEmpty { parts.append(protocolText) }
                let noteText = Common.edgeText(entry[Arch.noteKey] ?? "")
                if !noteText.isEmpty { parts.append(noteText) }
                let label = parts.joined(separator: " · ")
                let arrow = label.isEmpty ? " --> " : " -- \"\(label)\" --> "
                edges.append("  \(Common.diagramNodeID(node.id))\(arrow)\(target)")
            }
        }
        for stem in neighbours {
            guard let interface = interfaceByStem[stem] else { continue }
            lines.append("  \(Common.diagramNodeID(interface.id))[\"\(Common.cleanLabel(interface.title, dropParenthetical: true))\"]:::system")
        }
        lines += edges

        let entries = marked.values.sorted { a, b in
            a.nid != b.nid ? Common.less(a.nid, b.nid) : Common.less(a.key, b.key)
        }
        lines += model.lifecycleLines(entries)
        lines += Self.classes
        return lines.joined(separator: "\n")
    }
}
