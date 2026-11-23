import SwiftUI
import Systems42Kit

/// The term network as a projection mode (FR-040, FR-051): terms first, one toggle per page type to add its layer.
struct TermNetworkView: View {
    let session: WikiSession
    let model: TermNetworkModel
    let onSelect: (PageRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayerToggles(layers: model.layers, metamodel: session.metamodel, isOn: { model.isOn($0) }, toggle: { model.toggle($0) })
                .padding(.top, 8)
            if model.graph.nodes.isEmpty && model.isCurrent {
                Text(GraphModes.emptyHint(for: GraphModes.termNetwork))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiagramView(DiagramContent(.graph(model.graph, layout: DiagramLayout.termNetwork)), label: "Term network of the glossary",
                            title: { session.linkTitle(of: $0) }, fallbackText: nil,
                            frameColours: LayerColour.frames(of: model.layers, in: session.metamodel),
                            select: { if let ref = $0.ref { onSelect(ref) } })
                    .padding(10)
                    .opacity(model.isCurrent ? 1 : 0.45)
            }
        }
        .task(id: TermNetworkModel.Key(revision: session.revision, agreedOnly: session.agreedOnly, layers: model.enabled)) {
            await model.load()
        }
    }
}

extension WikiSession {
    /// The text of a node's link: the id and the title of its page, the node id when the page is gone.
    func linkTitle(of node: DiagramContent.Node) -> String {
        guard let ref = node.ref, let page = store.page(ref) else { return node.id }
        return ProjectionItem(page).text
    }
}
