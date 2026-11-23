import SwiftUI
import Systems42Kit

/// The term network as a projection mode (FR-040, FR-051): terms first, one toggle per page type to add its layer.
struct TermNetworkView: View {
    let session: WikiSession
    let model: TermNetworkModel
    let onSelect: (PageRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayerToggles(model: model).padding(.top, 8)
            if model.graph.nodes.isEmpty && model.isCurrent {
                Text(GraphModes.emptyHint(for: GraphModes.termNetwork))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiagramView(.graph(model.graph, layout: DiagramLayout.termNetwork), label: "Term network of the glossary",
                                allowsLinks: true, title: { session.pageTitle(forNode: $0, in: model.graph) }, fallbackText: nil,
                                select: { id in
                                    if let ref = DiagramContent(.graph(model.graph, layout: DiagramLayout.termNetwork)).node(id: id)?.ref { onSelect(ref) }
                                })
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
    /// The text of a node's link: the id and the title of its page, from the node's data when the page is gone.
    func pageTitle(forNode id: String, in graph: Graph) -> String {
        guard let node = graph.nodes.first(where: { $0.id == id }) else { return id }
        let label = node.data["label"]?.string ?? ""
        return label.isEmpty ? id : "\(id) \(label)"
    }
}
