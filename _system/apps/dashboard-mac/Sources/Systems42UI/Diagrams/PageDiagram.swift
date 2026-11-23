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
    private(set) var source: DiagramSource?
    @ObservationIgnored private var loadedRevision: Int?

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
            source = nil
            return
        }
        let revision = session.revision
        guard loadedRevision != revision else { return }
        await session.projections.load()
        guard session.revision == revision, session.projections.isCurrent, let projections = session.projections.data?.projections else { return }
        let stem = page.ref.stem
        let isTerm = session.metamodel.type(forFolder: ref.folder)?.projections.contains(GraphModes.termNetwork) == true
        let found = await Task.detached(priority: .userInitiated) { () -> DiagramSource? in
            if isTerm {
                let graph = projections.termNeighbourhood(of: stem)
                return graph.nodes.count > 1 ? .graph(graph, layout: DiagramLayout.termNetwork) : nil
            }
            guard let text = projections.mermaid("page-" + stem), DiagramContent(.mermaid(text)).drawsSomething else { return nil }
            return .mermaid(text)
        }.value
        guard !Task.isCancelled, session.revision == revision else { return }
        source = found
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
                    DiagramView(source, label: "Diagram of \(title)", allowsLinks: true, title: { id in
                        guard let ref = DiagramContent(source).node(id: id)?.ref, let page = session.store.page(ref) else { return id }
                        return ProjectionItem(page).text
                    }, fallbackText: nil, select: { id in
                        if let ref = DiagramContent(source).node(id: id)?.ref { session.open(.page(ref)) }
                    })
                }
            }
        }
        .task(id: session.revision) { await model.load() }
    }
}
