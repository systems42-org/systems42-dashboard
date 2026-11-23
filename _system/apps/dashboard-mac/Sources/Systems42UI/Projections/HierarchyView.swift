import SwiftUI
import Systems42Kit

/// The requirement hierarchy as an outline (FR-047). Selecting a node shows its page, and below the outline
/// its children and the building blocks that name it in `drivers:`.
struct HierarchyView: View {
    let model: ProjectionsModel
    let roots: [OutlineNode]
    let selected: PageRef?
    let onSelect: (PageRef) -> Void
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { selected }, set: { if let ref = $0 { onSelect(ref) } })) {
                ForEach(OutlineNode.flatten(roots, collapsed: collapsed), id: \.node.key) { row in
                    OutlineRowView(row: row) { toggle(row.node.key) }
                        .tag(row.node.item.ref)
                }
            }
            .listStyle(.inset)
            if let selected {
                Divider()
                DetailPanel(model: model, ref: selected, onSelect: onSelect)
                    .id(selected)
            }
        }
    }

    private func toggle(_ key: String) {
        if !collapsed.insert(key).inserted { collapsed.remove(key) }
    }
}

private struct OutlineRowView: View {
    let row: OutlineNode.Row
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
            if row.hasChildren {
                Button(action: toggle) {
                    Image(systemName: row.expanded ? "chevron.down" : "chevron.right").frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.expanded ? "Collapse \(row.node.item.id)" : "Expand \(row.node.item.id)")
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            Chip(text: row.node.level)
            Text(row.node.item.id).font(.system(.callout, design: .monospaced)).lineLimit(1)
            Text(row.node.item.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(row.node.item.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}

/// The children and the building blocks of the selected requirement. Nothing for a page outside the hierarchy.
private struct DetailPanel: View {
    let model: ProjectionsModel
    let ref: PageRef
    let onSelect: (PageRef) -> Void
    @State private var detail: HierarchyDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let detail {
                if detail.isEmpty {
                    Text("This requirement has no children and no building block.").foregroundStyle(.secondary)
                } else {
                    group("Children", detail.children)
                    group("Building blocks", detail.buildingBlocks)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .task { detail = await model.detail(of: ref) }
    }

    @ViewBuilder private func group(_ title: String, _ items: [ProjectionItem]) -> some View {
        if !items.isEmpty {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(items, id: \.key) { item in
                Button { if let ref = item.ref { onSelect(ref) } } label: {
                    Text(item.text).lineLimit(1).truncationMode(.tail)
                }
                .buttonStyle(.link)
                .accessibilityLabel("\(item.text), \(item.status)")
            }
        }
    }
}
