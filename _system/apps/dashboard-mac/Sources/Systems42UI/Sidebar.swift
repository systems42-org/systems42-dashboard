import SwiftUI
import Systems42Kit

/// The areas and sections of the wiki with their counts.
struct Sidebar: View {
    @Bindable var session: WikiSession
    @Environment(\.explain) private var explain

    var body: some View {
        // The rows are a `ForEach` over identifiable rows, so each row's id (a `String`) is its
        // selection value and no `.tag` is needed. The binding is `String?`, as the list wants.
        List(selection: Binding(get: { session.selectedSection }, set: { session.select(section: $0) })) {
            ForEach(session.sidebar) { group in
                SwiftUI.Section {
                    ForEach(group.rows) { row in
                        SidebarRowView(row: row, color: group.area.color) {
                            session.showIssues(of: row.section.id)
                        }
                        .contextMenu {
                            Button("About \(row.section.title)") { explain(.section(row.section.id)) }
                        }
                    }
                } header: {
                    Text(group.area.label).font(.caption.smallCaps()).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRowView: View {
    let row: SidebarRow
    let color: Color
    let showIssues: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
                Text(row.section.title).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(row.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            if (row.showsMaturity && row.count > 0) || row.openIssues > 0 {
                HStack(spacing: 6) {
                    if row.showsMaturity { MaturityBar(share: row.agreedShare) }
                    if row.openIssues > 0 {
                        Button(action: showIssues) {
                            Text("\(row.openIssues) open").font(.caption2)
                        }
                        .buttonStyle(.link)
                        .help("Show the open issues for this section")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
