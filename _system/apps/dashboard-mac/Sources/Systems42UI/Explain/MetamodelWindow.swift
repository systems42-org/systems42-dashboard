import AppKit
import SwiftUI
import Systems42Kit

/// The open wiki sessions by folder, so the Metamodel window finds the session of its wiki
/// and shares its metamodel instead of reading it a second time.
@MainActor enum OpenSessions {
    private final class Box {
        weak var session: WikiSession?
        init(_ session: WikiSession) { self.session = session }
    }

    private static var table: [URL: Box] = [:]

    static func register(_ session: WikiSession) {
        table = table.filter { $0.value.session != nil }
        table[session.root.url] = Box(session)
    }

    static func session(for folder: URL) -> WikiSession? {
        table[folder]?.session
    }
}

/// The wiki folder of the focused window, for the Help menu.
private struct WikiFolderKey: FocusedValueKey {
    typealias Value = URL
}

extension FocusedValues {
    var wikiFolder: URL? {
        get { self[WikiFolderKey.self] }
        set { self[WikiFolderKey.self] = newValue }
    }
}

/// The Metamodel window of one wiki, found by its folder.
public struct MetamodelWindowRoot: View {
    public static let windowID = "metamodel"
    let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public var body: some View {
        if let session = OpenSessions.session(for: folder) {
            MetamodelWindow(session: session)
                .focusedSceneValue(\.wikiFolder, folder)
        } else {
            Text("This wiki is closed.").foregroundStyle(.secondary).frame(minWidth: 400, minHeight: 200)
        }
    }
}

/// Help > Metamodel.
public struct MetamodelCommands: Commands {
    @FocusedValue(\.wikiFolder) private var folder
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .help) {
            Button("Metamodel") {
                if let folder { openWindow(id: MetamodelWindowRoot.windowID, value: folder) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(folder == nil)
        }
    }
}

/// Three columns: the kinds of construct, the entries of a kind, the entry (FR-010, FR-035).
struct MetamodelWindow: View {
    let session: WikiSession
    @Bindable private var model: MetamodelModel

    init(session: WikiSession) {
        self.session = session
        model = session.explainer
    }

    var body: some View {
        VStack(spacing: 0) {
            VersionNoticeLine(session: session)
            NavigationSplitView {
                List(model.kinds, id: \.self, selection: Binding(get: { model.selectedKind }, set: { if let kind = $0 { model.select(kind: kind) } })) { kind in
                    HStack {
                        Text(kind)
                        Spacer(minLength: 4)
                        Text("\(model.entries(of: kind).count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 240)
            } content: {
                EntryList(model: model)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 420)
            } detail: {
                EntryColumn(session: session, model: model)
            }
        }
        .environment(\.explain, ExplainAction { ExplainAction.apply($0, to: model) })
        .navigationTitle("Metamodel · \(session.title)")
        .frame(minWidth: 860, minHeight: 480)
    }
}

private struct EntryList: View {
    @Bindable var model: MetamodelModel

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedKind == MetamodelModel.types {
                Picker("Mode", selection: $model.mode) {
                    Text("Entries").tag(MetamodelModel.Mode.entries)
                    Text("Graph").tag(MetamodelModel.Mode.graph)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
            }
            if model.sectionFilter != nil {
                HStack {
                    Text("Types of one section").font(.callout)
                    Spacer(minLength: 4)
                    Button("Show all") { model.showAll() }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            List(model.shownEntries, selection: Binding(get: { model.selectedEntryID }, set: { model.select(entry: $0) })) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.title).lineLimit(1)
                    if !entry.definition.isEmpty {
                        Text(verbatim: entry.definition).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if model.shownEntries.isEmpty { Text("Nothing of this kind in this wiki.").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct EntryColumn: View {
    let session: WikiSession
    @Bindable var model: MetamodelModel

    var body: some View {
        Group {
            if model.showsVersionNotice, let notice = model.versionNotice {
                VersionExplanationView(notice: notice)
            } else if model.mode == .graph && model.selectedKind == MetamodelModel.types {
                GraphOutlineView(outline: model.graphOutline)
            } else if let entry = model.selectedEntry {
                switch entry.kind {
                case MetamodelModel.types: TypeEntryView(model: model, store: session.store, entry: entry)
                case MetamodelModel.anchors: AnchorEntryView(model: model, store: session.store, entry: entry)
                default: ConstructEntryView(model: model, store: session.store, entry: entry)
                }
            } else {
                Text("Choose an entry.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The Graph mode as data: types grouped by section, relations as lines. A web view draws it later (issue 128).
private struct GraphOutlineView: View {
    let outline: MetamodelModel.GraphOutline

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(outline.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: group.title).font(.headline)
                        ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
                    }
                }
                Text("Relations").font(.headline)
                ForEach(Array(outline.relations.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.system(.callout, design: .monospaced))
                }
                if !outline.universal.isEmpty {
                    Text("Relations of every type").font(.headline)
                    ForEach(Array(outline.universal.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.system(.callout, design: .monospaced))
                    }
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Parts the entry views share

/// The scroll frame of an entry: a title, then its content.
struct EntryFrame<Content: View>: View {
    let entry: MetamodelModel.Entry
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: entry.kind).font(.caption.smallCaps()).foregroundStyle(.secondary)
                Text(verbatim: entry.title).font(.title.bold()).accessibilityAddTraits(.isHeader)
                if !entry.definition.isEmpty { Text(verbatim: entry.definition).font(.title3) }
                content
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FactsView: View {
    let facts: [MetamodelModel.Fact]

    var body: some View {
        if !facts.isEmpty {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    GridRow {
                        Text(verbatim: fact.label).foregroundStyle(.secondary)
                        Text(verbatim: fact.value)
                    }
                }
            }
        }
    }
}

/// Links to other entries.
struct LinkGroupsView: View {
    let model: MetamodelModel
    let groups: [MetamodelModel.LinkGroup]

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: group.title).font(.headline)
                HStack(spacing: 8) {
                    ForEach(Array(group.links.enumerated()), id: \.offset) { _, link in
                        Button(link.title) { model.show(link: link) }.buttonStyle(.link)
                    }
                }
            }
        }
    }
}

/// The body of a metamodel page, as formatted text. Its links lead to other entries.
struct EntryBody: View {
    let model: MetamodelModel
    let store: WikiStore
    let entry: MetamodelModel.Entry
    @State private var rendered: [Block] = []

    var body: some View {
        BlockList(blocks: rendered)
            .environment(\.pageLinks, PageLinks(
                open: { action in
                    switch action {
                    case .anchor(let name): model.show(.anchor(name))
                    case .metamodel(let name): model.show(.metamodel(name))
                    case .web(let url): NSWorkspace.shared.open(url)
                    case .page: break
                    }
                },
                definition: { _, _ in nil }
            ))
            .task(id: entry.id + entry.body) {
                guard !entry.body.isEmpty else { rendered = []; return }
                rendered = await PageModel.renderBody(entry.body, store).blocks
            }
    }
}
