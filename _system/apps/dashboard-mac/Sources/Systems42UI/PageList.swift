import SwiftUI
import Systems42Kit

/// The middle column: the list of the selected section, or a hint while none is selected.
struct ListColumn: View {
    let session: WikiSession
    @Binding var storedStates: String

    var body: some View {
        if let id = session.selectedSection, let section = session.metamodel.sections.first(where: { $0.id == id }) {
            // A new section gets a new model, with the state it had when it was last shown.
            PageList(session: session, section: section, storedStates: $storedStates)
                .id(section.id)
        } else {
            Text("Choose a section.").foregroundStyle(.secondary)
        }
    }
}

/// Builds the model once, when the list appears. A new section makes a new `PageList`.
struct PageList: View {
    let session: WikiSession
    let section: WikiSection
    @Binding var storedStates: String
    @State private var model: ListModel?

    var body: some View {
        if let model {
            PageListContent(session: session, model: model, storedStates: $storedStates)
        } else {
            Color.clear.onAppear {
                model = ListModel(session: session, section: section, state: ListStates.decode(storedStates)[section.id])
            }
        }
    }
}

private struct PageListContent: View {
    let session: WikiSession
    let model: ListModel
    @Binding var storedStates: String

    var body: some View {
        let rows = model.rows
        VStack(spacing: 0) {
            if let restriction = model.issueRestriction {
                HStack {
                    Text(restriction).font(.callout)
                    Spacer(minLength: 4)
                    Button("Show all") { model.clearIssueRestriction() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
            }
            // Clicking empty space sends nil. The session keeps its page then, so the highlight and the page column agree.
            List(selection: Binding(get: { session.selectedPage }, set: { if let ref = $0 { model.select(ref) } })) {
                ForEach(rows, id: \.ref) { page in
                    PageRow(page: page, badges: model.badges(of: page))
                }
            }
            .listStyle(.inset)
            .overlay {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Text(model.hasFilters ? "No page matches the filters." : "No pages yet.").foregroundStyle(.secondary)
                        if model.hasFilters { Button("Clear filters") { model.clearFilters() } }
                    }
                }
            }
        }
        .toolbar { ListToolbar(model: model) }
        .onChange(of: model.state) { _, state in
            storedStates = ListStates.updating(storedStates, section: model.sectionID, with: state)
        }
    }
}

private struct PageRow: View {
    let page: Page
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(page.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
            }
            .lineLimit(1)
            Text(page.title).lineLimit(2)
        }
        .padding(.vertical, 2)
        .tag(page.ref)
        .accessibilityElement(children: .combine)
    }
}
