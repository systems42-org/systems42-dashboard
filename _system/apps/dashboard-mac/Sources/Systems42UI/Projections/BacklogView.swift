import SwiftUI
import Systems42Kit

/// The backlog: the requirements ranked by release, priority, order and id (`proj-backlog-ranking`).
struct BacklogView: View {
    let rows: [BacklogRow]
    let selected: PageRef?
    let onSelect: (PageRef) -> Void

    var body: some View {
        List(selection: Binding(get: { selected }, set: { if let ref = $0 { onSelect(ref) } })) {
            ForEach(rows, id: \.item.key) { row in
                HStack(spacing: 8) {
                    Text("\(row.rank)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Text(row.item.id).font(.system(.callout, design: .monospaced)).lineLimit(1).frame(width: 90, alignment: .leading)
                    Text(row.item.title).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    if !row.level.isEmpty { Chip(text: row.level) }
                    if !row.release.isEmpty { Chip(text: row.release) }
                    if !row.priority.isEmpty { Chip(text: row.priority) }
                    Text(row.item.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
                .tag(row.item.ref)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
            }
        }
        .listStyle(.inset)
    }
}
