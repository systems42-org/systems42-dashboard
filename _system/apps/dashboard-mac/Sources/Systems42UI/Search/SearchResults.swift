import SwiftUI
import Systems42Kit

/// The list column while a search is shown: filters, the hits and the related pages (FR-007 to FR-009).
struct SearchResults: View {
    let session: WikiSession
    @Bindable var model: SearchModel
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(session: session, model: model)
            Divider()
            List(selection: Binding(get: { session.selectedPage }, set: { ref in
                guard let ref, let hit = (model.hits + model.related).first(where: { $0.ref == ref }) else { return }
                model.open(hit, keepingResults: true)
            })) {
                if !model.hits.isEmpty {
                    Section("Hits") {
                        ForEach(model.hits, id: \.ref) { hit in SearchResultRow(hit: hit) }
                    }
                }
                if !model.related.isEmpty {
                    Section("Related pages") {
                        ForEach(model.related, id: \.ref) { hit in SearchResultRow(hit: hit) }
                    }
                }
            }
            .listStyle(.inset)
            .focused($listFocused)
            .onChange(of: model.listFocusRequests) { if model.takeListFocus() { listFocused = true } }
            .onAppear { if model.takeListFocus() { listFocused = true } }
            .overlay { SearchState(model: model) }
        }
    }
}

private struct SearchHeader: View {
    let session: WikiSession
    let model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Results for “\(session.shownSearch?.query ?? "")”").font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Button("Close") { session.closeSearch() }
                    .help("Back to the pages of the section")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SearchFilterFields.all, id: \.name) { field in
                        FilterButton(model: model, field: field.name)
                    }
                    Button("Clear filters") { model.clearFilter() }
                        .disabled(!model.hasFilter)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct FilterButton: View {
    let model: SearchModel
    let field: String

    var body: some View {
        let options = model.options(for: field)
        let chosen = options.filter { model.isSelected(field: field, value: $0.value) }.count
        Menu {
            ForEach(options) { option in
                Toggle("\(option.label) (\(option.count))", isOn: Binding(
                    get: { model.isSelected(field: field, value: option.value) },
                    set: { _ in model.toggle(field: field, value: option.value) }
                ))
            }
        } label: {
            Text(chosen == 0 ? FieldLabel.text(field) : "\(FieldLabel.text(field)) · \(chosen)")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(options.isEmpty)
        .accessibilityLabel("Filter by \(FieldLabel.text(field).lowercased())")
        .accessibilityValue(chosen == 0 ? "off" : "\(chosen) chosen")
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(hit.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ForEach([hit.type, hit.status].filter { !$0.isEmpty }, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
            }
            .lineLimit(1)
            Text(hit.title).lineLimit(2)
            if let note = hit.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if let passage = hit.passage, !passage.text.isEmpty {
                Text(passage.attributed).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(.vertical, 2)
        .tag(hit.ref)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SearchRows.spoken(hit))
        .accessibilityValue(hit.passage?.text ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

private struct SearchState: View {
    let model: SearchModel

    var body: some View {
        if model.isIndexing {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Still indexing the wiki.").foregroundStyle(.secondary)
            }
        } else if model.hits.isEmpty && model.related.isEmpty {
            VStack(spacing: 8) {
                Text(model.hasFilter ? "No page matches the words and the filters." : "No page matches.").foregroundStyle(.secondary)
                if model.hasFilter { Button("Clear filters") { model.clearFilter() } }
            }
        }
    }
}

/// The marks of the query words in the page column.
private struct PageMarksKey: EnvironmentKey {
    static let defaultValue = PageMarks.none
}

extension EnvironmentValues {
    var pageMarks: PageMarks {
        get { self[PageMarksKey.self] }
        set { self[PageMarksKey.self] = newValue }
    }
}
