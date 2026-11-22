import Foundation

/// The metamodel as a graph: framework blocks as groups, content types as nodes, relations as edges.
/// Port of `buildMetamodelGraph` in `internal/web/metamodel.go`, with the ordering of
/// `Reader.Load` in `internal/metamodel/metamodel.go`.
///
/// Open debt (CON-006): the graph reads the metamodel itself. The order of the frameworks, the keys of a
/// relation page and the node key names are the dashboard's.
struct MetamodelGraphProjection {
    let metamodel: Metamodel

    /// Frameworks in this order, others after. Go: metamodel.go `frameworkOrder`.
    static let frameworkOrder = ["req42", "commons", "arc42"]
    /// Keys of a relation page. Go: `buildMetamodelGraph`.
    static let directionKey = "direction", semanticsKey = "semantics", edgesKey = "edges"
    static let fromKey = "from", toKey = "to", cardinalityKey = "cardinality", noteKey = "note"
    static let symmetric = "symmetric"
    /// A relation end that stands for every type. Go: `buildMetamodelGraph`.
    static let anyType = "any"
    static let blockPrefix = "block:", typeAnchor = "#type-"
    /// The directions of a loop edge, one per loop on the same type. Go: `loopDirs`.
    static let loopDirections = ["-45deg", "45deg", "135deg", "-135deg"]

    private func text(_ value: String) -> GraphValue { .string(value) }

    func graph() -> Graph {
        let frameworks = metamodel.frameworks.enumerated().sorted { a, b in
            let ra = Self.frameworkOrder.firstIndex(of: a.element.name) ?? 99
            let rb = Self.frameworkOrder.firstIndex(of: b.element.name) ?? 99
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)

        var blocks: [(id: String, title: String, area: String)] = []
        var blockPosition: [String: Int] = [:]
        for framework in frameworks {
            for block in framework.blocks {
                blockPosition[block.id] = blocks.count
                blocks.append((block.id, block.title, framework.area))
            }
        }
        let types = metamodel.types.enumerated().sorted { a, b in
            let pa = blockPosition[a.element.block] ?? blocks.count, pb = blockPosition[b.element.block] ?? blocks.count
            if pa != pb { return pa < pb }
            return a.element.name == b.element.name ? a.offset < b.offset : Common.less(a.element.name, b.element.name)
        }.map(\.element)

        let usedBlocks = Set(types.map(\.block).filter { !$0.isEmpty })
        var nodes: [Graph.Node] = []
        for block in blocks where usedBlocks.contains(block.id) {
            nodes.append(Graph.Node(data: [
                "id": text(Self.blockPrefix + block.id), "label": text(block.id + " · " + block.title),
                "is_block": .bool(true), "area": text(block.area),
            ]))
        }
        for type in types {
            var data: [String: GraphValue] = [
                "id": text(type.name), "label": text(type.label.isEmpty ? type.name : type.label), "prefix": text(type.prefix),
                "label_de": text(type.labelDe), "url": text(Self.typeAnchor + type.name),
                "stereotypes": text(type.stereotypes.joined(separator: ", ")), "block_id": text(type.block),
            ]
            if !type.block.isEmpty { data["parent"] = text(Self.blockPrefix + type.block) }
            nodes.append(Graph.Node(data: data))
        }

        let names = Set(types.map(\.name))
        var edges: [Graph.Edge] = []
        var universal: [GraphValue] = []
        var loops: [String: Int] = [:]
        for relation in metamodel.relations {
            let field = relation.storedField ?? ""
            var direction = ""
            if case .text(let value)? = relation.frontmatter[Self.directionKey] { direction = value }
            var semantics = ""
            if case .text(let value)? = relation.frontmatter[Self.semanticsKey] { semantics = value }
            for entry in relation.entries[Self.edgesKey] ?? [] {
                let source = entry[Self.fromKey] ?? "", target = entry[Self.toKey] ?? ""
                if source == Self.anyType || target == Self.anyType {
                    universal.append(.map([
                        "field": text(field), "from": text(source), "to": text(target), "direction": text(direction),
                        "cardinality": text(entry[Self.cardinalityKey] ?? ""), "note": text(entry[Self.noteKey] ?? ""),
                    ]))
                    continue
                }
                guard names.contains(source), names.contains(target) else { continue }
                var data: [String: GraphValue] = [
                    "id": text("e\(edges.count)"), "source": text(source), "target": text(target), "label": text(field),
                    "cardinality": text(entry[Self.cardinalityKey] ?? ""), "semantics": text(semantics),
                    "symmetric": .bool(direction == Self.symmetric), "note": text(entry[Self.noteKey] ?? ""),
                ]
                if source == target {
                    let index = loops[source] ?? 0
                    loops[source] = index + 1
                    data["loop_dir"] = text(Self.loopDirections[index % Self.loopDirections.count])
                }
                edges.append(Graph.Edge(data: data))
            }
        }
        return Graph(nodes: nodes, edges: edges, extra: ["universal": .list(universal)])
    }
}
