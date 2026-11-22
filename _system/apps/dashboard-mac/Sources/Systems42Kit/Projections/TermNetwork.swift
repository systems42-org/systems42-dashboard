import Foundation

/// The term network: domain terms as nodes, `related:` links and structured relationships as edges, plus
/// the pages of other types that terms link to (DR-023, FR-040, FR-051, FR-052). Port of
/// `BuildGlossaryGraph` and `BuildGlossaryEgoGraph` in `internal/project/glossary.go`.
///
/// Open debt (CON-006): `proj-terminology-graph` declares the type and the fields it reads. The node and
/// edge keys the graph carries, and the state words, are the dashboard's.
struct TermNetworkProjection {
    let model: ProjectionModel

    // Content types. Go: glossary.go `namedGraphTypes`, `egoTypes` (written there as id prefixes).
    static let termType = "domain-term"
    /// The types of the neighbours that have a layer of their own. Go: `namedGraphTypes`.
    static let namedTypes = ["stakeholder", "external-interface", "goal", "building-block"]
    /// The types an ego graph keeps beside the term itself. Go: `egoTypes`.
    static let egoTypes = ["domain-term", "stakeholder", "goal", "building-block"]

    // Relations by name and fields. Go: glossary.go `p.AsList("related")`, `p.Meta["agreed"]`.
    static let relatedRelation = "related"
    static let agreedField = "agreed"
    // Values. Go: glossary.go `BuildGlossaryGraph`.
    static let deprecatedStatus = "deprecated"
    static let assumptionMarker = "[!assumption]"
    static let urlPrefix = "/page/"
    /// The edge filters of the route `/graph/domain-terms?edges=`. Go: web/projections.go `handleGlossaryGraph`.
    enum Edges: String { case all, related, structured }

    private struct Pair: Hashable {
        let a, b: String
        init(_ x: String, _ y: String) { (a, b) = Common.less(x, y) ? (x, y) : (y, x) }
    }

    private struct StructuredKey: Hashable {
        let source, target, kind, label, cardinality: String
    }

    /// Go: `wiki.TypeOf`, the id prefix before the first dash.
    private func typeOf(_ stem: String) -> String {
        stem.firstIndex(of: "-").map { String(stem[..<$0]) } ?? stem
    }

    private func prefixes(of types: [String]) -> Set<String> {
        Set(types.compactMap { model.prefix(ofType: $0) })
    }

    private func isAgreed(_ page: Page) -> Bool {
        if case .text(let value)? = page.fields[Self.agreedField] { return ["true", "True", "TRUE"].contains(value) }
        return false
    }

    private func text(_ value: String) -> GraphValue { .string(value) }

    /// Ports `BuildGlossaryGraph`.
    func graph(edges filter: Edges) -> Graph {
        let glossary = model.pages(ofType: Self.termType)
        let termPrefix = model.prefix(ofType: Self.termType) ?? ""
        let named = prefixes(of: Self.namedTypes)
        let glossaryStems = Set(glossary.map(\.stem))
        var degree: [String: Int] = [:]
        for page in glossary { degree[page.stem] = 0 }

        var seenPairs = Set<Pair>()
        var edges: [[String: GraphValue]] = []
        var neighbourStems = Set<String>()
        let relatedField = model.field(ofRelation: Self.relatedRelation)

        if filter != .structured {
            for page in glossary {
                let source = page.stem
                for target in page.names(relatedField) {
                    guard !target.isEmpty, target != source, model.byStem[target] != nil else { continue }
                    guard seenPairs.insert(Pair(source, target)).inserted else { continue }
                    let cross = !glossaryStems.contains(target)
                    var edge: [String: GraphValue] = [
                        "id": text("e\(edges.count)"), "source": text(source), "target": text(target),
                        "cross": .bool(cross), "kind": text("related"),
                    ]
                    if cross {
                        edge["ntype"] = text(typeOf(target))
                        neighbourStems.insert(target)
                    } else {
                        degree[source, default: 0] += 1
                        degree[target, default: 0] += 1
                    }
                    edges.append(edge)
                }
            }
        }

        if filter != .related {
            var seen = Set<StructuredKey>()
            let data = DataModelProjection(model: model)
            for relation in data.edges(of: data.nodes()) {
                guard glossaryStems.contains(relation.source), glossaryStems.contains(relation.target) else { continue }
                let key = StructuredKey(source: relation.source, target: relation.target, kind: relation.kind,
                                        label: relation.verb, cardinality: relation.cardinality)
                guard seen.insert(key).inserted else { continue }
                edges.append([
                    "id": text("e\(edges.count)"), "source": text(relation.source), "target": text(relation.target),
                    "cross": .bool(false), "kind": text(relation.kind),
                    "label": text(relation.verb.isEmpty ? relation.kind : relation.verb),
                ])
                degree[relation.source, default: 0] += 1
                degree[relation.target, default: 0] += 1
            }
        }

        var nodes: [[String: GraphValue]] = []
        for page in glossary {
            var state = "draft"
            if page.status == Self.deprecatedStatus { state = "deprecated" } else if isAgreed(page) { state = "agreed" }
            nodes.append([
                "id": text(page.stem), "label": text(page.title), "type": text(termPrefix), "core": .bool(true),
                "url": text(Self.urlPrefix + page.ref.folder + "/" + page.stem), "degree": .int(degree[page.stem] ?? 0),
                "state": text(state), "assumption": .bool(page.body.contains(Self.assumptionMarker)),
                "aliases": text(page.aliases.joined(separator: ", ")),
            ])
        }
        for stem in neighbourStems.sorted(by: Common.less) {
            guard let page = model.byStem[stem] else { continue }
            let type = typeOf(stem)
            var node: [String: GraphValue] = [
                "id": text(stem), "label": text(page.title), "type": text(type), "core": .bool(false),
                "url": text(Self.urlPrefix + page.ref.folder + "/" + stem),
            ]
            if !named.contains(type) { node["rest"] = .int(1) }
            nodes.append(node)
        }

        var layerCounts: [String: GraphValue] = [:]
        for edge in edges where edge["cross"]?.bool == true {
            if let type = edge["ntype"]?.string { layerCounts[type] = .int(((layerCounts[type].flatMap(intValue)) ?? 0) + 1) }
        }
        return Graph(nodes: nodes.map(Graph.Node.init(data:)), edges: edges.map(Graph.Edge.init(data:)),
                     extra: ["layer_counts": .map(layerCounts)])
    }

    private func intValue(_ value: GraphValue) -> Int? {
        if case .int(let number) = value { return number }
        return nil
    }

    /// Ports `BuildGlossaryEgoGraph`: the term and its neighbours of the kinds an ego graph shows.
    /// An empty graph when the stem is no node of the network.
    func ego(of stem: String) -> Graph {
        let full = graph(edges: .all)
        let egoPrefixes = prefixes(of: Self.egoTypes)
        var nodeByID: [String: [String: GraphValue]] = [:]
        for node in full.nodes { nodeByID[node.id] = node.data }
        guard nodeByID[stem] != nil else { return Graph() }

        var neighbours = Set<String>()
        for edge in full.edges {
            if edge.source == stem { neighbours.insert(edge.target) } else if edge.target == stem { neighbours.insert(edge.source) }
        }
        var egoIDs: Set<String> = [stem]
        for id in neighbours {
            if let type = nodeByID[id]?["type"]?.string, egoPrefixes.contains(type) { egoIDs.insert(id) }
        }

        var nodes: [Graph.Node] = []
        for id in egoIDs.sorted(by: Common.less) {
            var data = nodeByID[id] ?? [:]
            if id == stem { data["focus"] = .bool(true) }
            nodes.append(Graph.Node(data: data))
        }
        var edges: [Graph.Edge] = []
        var layerCounts: [String: GraphValue] = [:]
        for edge in full.edges where egoIDs.contains(edge.source) && egoIDs.contains(edge.target) {
            edges.append(edge)
            if edge.data["cross"]?.bool == true, let type = edge.data["ntype"]?.string, egoPrefixes.contains(type) {
                layerCounts[type] = .int((layerCounts[type].flatMap(intValue) ?? 0) + 1)
            }
        }
        return Graph(nodes: nodes, edges: edges, extra: ["layer_counts": .map(layerCounts)])
    }

    /// The network with some layers on: the terms, and the neighbours of the given types. A neighbour is
    /// by construction next to a term. Edges stay when both ends stay.
    func layered(_ layers: Set<String>) -> Graph {
        let full = graph(edges: .all)
        let shownPrefixes = prefixes(of: Array(layers))
        let nodes = full.nodes.filter { node in
            node.data["core"]?.bool == true || (node.data["type"]?.string).map(shownPrefixes.contains) == true
        }
        let ids = Set(nodes.map(\.id))
        let edges = full.edges.filter { ids.contains($0.source) && ids.contains($0.target) }
        var layerCounts: [String: GraphValue] = [:]
        for edge in edges where edge.data["cross"]?.bool == true {
            if let type = edge.data["ntype"]?.string { layerCounts[type] = .int((layerCounts[type].flatMap(intValue) ?? 0) + 1) }
        }
        return Graph(nodes: nodes, edges: edges, extra: ["layer_counts": .map(layerCounts)])
    }
}
