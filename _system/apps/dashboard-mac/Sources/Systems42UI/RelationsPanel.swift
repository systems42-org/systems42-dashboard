import SwiftUI
import Systems42Kit

/// The pages this page links to and the pages that link here, grouped by relation.
struct RelationsPanel: View {
    let outgoing: [PageModel.RelationGroup]
    let incoming: [PageModel.RelationGroup]
    @Environment(\.pageLinks) private var links

    var body: some View {
        if !outgoing.isEmpty || !incoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Relations").font(.headline)
                section("Links to", outgoing)
                section("Linked from", incoming)
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ groups: [PageModel.RelationGroup]) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: group.label).font(.caption).foregroundStyle(.secondary)
                        ForEach(group.pages, id: \.ref) { page in
                            Button { links.open(.page(page.ref)) } label: {
                                Text(verbatim: "\(page.id)  \(page.title)").lineLimit(1)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
        }
    }
}
