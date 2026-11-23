import Foundation
import Observation
import SwiftUI
import Systems42Kit

/// The diagram that belongs to one page: a term's neighbourhood (FR-052), the white box of a building
/// block, the sequence of a runtime scenario, a deployment node's subtree, a requirement's breakdown.
/// The model holds the session weakly and drops a result of an older revision.
@MainActor @Observable final class PageDiagramModel {
    private weak var session: WikiSession?
    let ref: PageRef
    /// What a diagram that is no term network shows.
    private var base: DiagramSource?
    /// The term's whole neighbourhood, with every layer.
    private var neighbourhood: Graph?
    /// The layers of the neighbourhood, and the ones that are on. A term page opens with terms only.
    private(set) var layers: [TermNetworkModel.Layer] = []
    private(set) var enabled: Set<String> = []
    @ObservationIgnored private var loadedRevision: Int?

    /// What the page shows now.
    var source: DiagramSource? {
        guard let neighbourhood else { return base }
        let prefixes = Set(layers.filter { enabled.contains($0.id) }.map(\.prefix))
        return .graph(Self.filtered(neighbourhood, prefixes: prefixes), layout: DiagramLayout.termNetwork)
    }

    func toggle(_ layer: String) {
        if enabled.contains(layer) { enabled.remove(layer) } else if layers.contains(where: { $0.id == layer }) { enabled.insert(layer) }
    }

    /// The terms, and the neighbours of the given type prefixes. An edge stays when both ends stay.
    nonisolated static func filtered(_ graph: Graph, prefixes: Set<String>) -> Graph {
        let nodes = graph.nodes.filter { $0.data["core"]?.bool == true || ($0.data["type"]?.string).map(prefixes.contains) == true }
        let ids = Set(nodes.map(\.id))
        return Graph(nodes: nodes, edges: graph.edges.filter { ids.contains($0.source) && ids.contains($0.target) }, extra: graph.extra)
    }

    /// One layer per type of neighbour in the term's neighbourhood, with the edges it adds.
    nonisolated static func layers(of graph: Graph, metamodel: Metamodel) -> [TermNetworkModel.Layer] {
        var counts: [String: Int] = [:]
        if case .map(let found)? = graph.extra["layer_counts"] {
            for (prefix, value) in found { if case .int(let n) = value { counts[prefix] = n } }
        }
        var seen = Set<String>()
        return metamodel.types.compactMap { type in
            guard let count = counts[type.prefix], seen.insert(type.prefix).inserted else { return nil }
            return TermNetworkModel.Layer(id: type.name, prefix: type.prefix, label: type.label.isEmpty ? type.name : type.label, count: count)
        }
    }

    init(session: WikiSession, ref: PageRef) {
        self.session = session
        self.ref = ref
    }

    /// The projections that give a page a diagram of its own.
    static let projections = [GraphModes.termNetwork, GraphModes.buildingBlocks, GraphModes.deployment, GraphModes.context,
                              "whitebox", "sequence-diagram", ProjectionHost.storyMapMode]

    /// Whether the type of the page declares a projection that draws it.
    static func wantsDiagram(_ page: Page, metamodel: Metamodel) -> Bool {
        guard let type = metamodel.type(forFolder: page.ref.folder) else { return false }
        return type.projections.contains { projections.contains($0) }
    }

    func load() async {
        guard let session, let page = session.store.page(ref), Self.wantsDiagram(page, metamodel: session.metamodel) else {
            base = nil
            neighbourhood = nil
            return
        }
        let revision = session.revision
        guard loadedRevision != revision else { return }
        await session.projections.load()
        guard session.revision == revision, session.projections.isCurrent, let projections = session.projections.latest?.projections else { return }
        let stem = page.ref.stem
        let metamodel = session.metamodel
        let isTerm = session.metamodel.type(forFolder: ref.folder)?.projections.contains(GraphModes.termNetwork) == true
        let found = await Task.detached(priority: .userInitiated) { () -> (source: DiagramSource?, graph: Graph?, layers: [TermNetworkModel.Layer]) in
            if isTerm {
                let graph = projections.termNeighbourhood(of: stem)
                return graph.nodes.count > 1 ? (nil, graph, Self.layers(of: graph, metamodel: metamodel)) : (nil, nil, [])
            }
            guard let text = projections.mermaid("page-" + stem), DiagramContent(.mermaid(text)).drawsSomething else { return (nil, nil, []) }
            return (.mermaid(text), nil, [])
        }.value
        guard !Task.isCancelled, session.revision == revision else { return }
        base = found.source
        neighbourhood = found.graph
        layers = found.layers
        enabled.formIntersection(Set(found.layers.map(\.id)))
        loadedRevision = revision
    }
}

/// The diagram under a page body, when the page has one.
struct PageDiagram: View {
    let session: WikiSession
    let ref: PageRef
    @State private var model: PageDiagramModel

    init(session: WikiSession, ref: PageRef) {
        self.session = session
        self.ref = ref
        _model = State(initialValue: PageDiagramModel(session: session, ref: ref))
    }

    var body: some View {
        Group {
            if let source = model.source {
                let title = session.store.page(ref)?.title ?? ref.stem
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagram").font(.headline).accessibilityAddTraits(.isHeader)
                    LayerToggles(layers: model.layers, metamodel: session.metamodel, isOn: { model.enabled.contains($0) }, toggle: { model.toggle($0) })
                    DiagramView(DiagramContent(source), label: "Diagram of \(title)", title: { session.linkTitle(of: $0) }, fallbackText: nil,
                                frameColours: LayerColour.frames(of: model.layers, in: session.metamodel),
                                select: { if let ref = $0.ref { session.open(.page(ref)) } })
                }
            }
        }
        .task(id: session.revision) { await model.load() }
    }
}
