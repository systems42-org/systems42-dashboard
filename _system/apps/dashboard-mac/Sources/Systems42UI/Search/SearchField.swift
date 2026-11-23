import SwiftUI
import Systems42Kit

/// The search field in the window toolbar. Typing shows suggestions (`SuggestionList`), Return shows
/// the full list, the arrow keys move through the suggestions and Escape closes them.
struct SearchField: View {
    @Bindable var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search (⌘K)", text: $model.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .accessibilityLabel("Search the wiki")
                .accessibilityHint("Type to see suggestions. Down arrow chooses one, Return opens it or shows all results, Escape closes the suggestions.")
                .onSubmit { model.submit() }
                .onKeyPress(.downArrow) { model.moveHighlight(by: 1) ? .handled : .ignored }
                .onKeyPress(.upArrow) { model.moveHighlight(by: -1) ? .handled : .ignored }
                .onExitCommand { model.dismissSuggestions() }
            if !model.query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: 240)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: model.focusRequests) { focused = true }
        .onChange(of: focused) { _, now in if !now { model.dismissSuggestions() } }
    }
}

/// The suggestions under the field: at most 8 titles, each with its reason. No passages, no related pages.
struct SuggestionList: View {
    let model: SearchModel

    var body: some View {
        if model.suggestionsOpen {
            VStack(alignment: .leading, spacing: 0) {
                if model.showsIndexing {
                    Text("Still indexing the wiki.").foregroundStyle(.secondary).padding(8)
                } else if model.quick.isEmpty {
                    Text("No page matches.").foregroundStyle(.secondary).padding(8)
                } else {
                    ForEach(Array(model.quick.enumerated()), id: \.element.ref) { position, hit in
                        Button { model.open(hit) } label: {
                            SuggestionRow(hit: hit)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(position == model.highlighted ? Color.accentColor.opacity(0.25) : .clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(SearchRows.spoken(hit))
                        .accessibilityAddTraits(position == model.highlighted ? .isSelected : [])
                    }
                }
            }
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .shadow(radius: 6, y: 2)
            .padding(.top, 4)
            .padding(.trailing, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Suggestions")
        }
    }
}

private struct SuggestionRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(hit.title).lineLimit(1)
                Spacer(minLength: 4)
                Text(hit.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let note = hit.note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// What a result row says, in the words a screen reader reads: the title and id, then the reason.
enum SearchRows {
    static func spoken(_ hit: SearchHit) -> String {
        let head = "\(hit.title), \(hit.id)"
        guard let note = hit.note else { return head }
        return "\(head). \(note)"
    }
}

private struct WikiSearchKey: FocusedValueKey {
    typealias Value = SearchModel
}

extension FocusedValues {
    var wikiSearch: SearchModel? {
        get { self[WikiSearchKey.self] }
        set { self[WikiSearchKey.self] = newValue }
    }
}

/// Cmd-K (FR-001) and Cmd-F put the keyboard focus in the search field of the front wiki window.
public struct SearchCommands: Commands {
    @FocusedValue(\.wikiSearch) private var search

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search the Wiki") { search?.focusField() }
                .keyboardShortcut("k")
                .disabled(search == nil)
            Button("Find in the Wiki") { search?.focusField() }
                .keyboardShortcut("f")
                .disabled(search == nil)
        }
    }
}
