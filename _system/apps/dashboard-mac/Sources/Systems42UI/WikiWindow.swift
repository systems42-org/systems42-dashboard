import SwiftUI
import Systems42Kit

/// One window per wiki: sections, list, page. The page column shows the selected page, or the vision while none is selected.
public struct WikiWindow: View {
    @Bindable var session: WikiSession
    @SceneStorage("selectedSection") private var storedSection = ""
    @SceneStorage("listStates") private var storedListStates = ""
    @Environment(\.openWindow) private var openWindow

    init(session: WikiSession) {
        self.session = session
    }

    /// Shows the section in the mode this window stored for it, when it was not shown in one yet.
    private func adoptStoredMode() {
        guard let id = session.selectedSection, let stored = ListStates.decode(storedListStates)[id]?.mode else { return }
        session.adopt(mode: stored, in: id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            VersionNoticeLine(session: session)
            if session.showsProjection {
                // A projection takes the width of the list and the page. The page opens beside it.
                NavigationSplitView {
                    Sidebar(session: session)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
                } detail: {
                    ProjectionColumn(session: session)
                }
            } else {
                NavigationSplitView {
                    Sidebar(session: session)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
                } content: {
                    ListColumn(session: session, storedStates: $storedListStates)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 480)
                } detail: {
                    PagePlaceholder(session: session)
                }
            }
            TourPanel(tour: session.tour)
        }
        .overlay(alignment: .topTrailing) { SuggestionList(model: session.search) }
        .toolbar {
            ToolbarItem { PageActionsMenu(session: session) }
            ToolbarItem { SearchField(model: session.search) }
        }
        .focusedSceneValue(\.wikiSearch, session.search)
        .onChange(of: session.shownSearch) { _, _ in session.search.followSession() }
        .onChange(of: session.selectedPage) { _, _ in session.search.followSelection() }
        .onChange(of: session.revision) { _, _ in session.search.followWiki() }
        .environment(\.explain, ExplainAction { target in
            ExplainAction.apply(target, to: session.explainer)
            openWindow(id: MetamodelWindowRoot.windowID, value: session.root.url)
        })
        .focusedSceneValue(\.wikiFolder, session.root.url)
        .navigationTitle(session.title)
        .navigationSubtitle(session.subtitle ?? "")
        .onAppear {
            if session.selectedSection == nil, session.metamodel.sections.contains(where: { $0.id == storedSection }) {
                session.select(section: storedSection)
            }
            adoptStoredMode()
        }
        .onChange(of: session.selectedSection) { _, id in
            storedSection = id ?? ""
            adoptStoredMode()
        }
        .onChange(of: session.mode) { _, mode in
            // The mode is remembered per section like sort and filter, in the window's restored state.
            guard let id = session.selectedSection, session.shownSearch == nil else { return }
            var state = ListStates.decode(storedListStates)[id] ?? ListState(mode: mode)
            state.mode = mode
            storedListStates = ListStates.updating(storedListStates, section: id, with: state)
        }
        .focusedSceneValue(\.wikiSession, session)
    }
}

private struct PagePlaceholder: View {
    let session: WikiSession

    var body: some View {
        if let ref = session.selectedPage {
            PageColumn(session: session, ref: ref)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let orientation = session.orientation {
                    Text(orientation.title).font(.title)
                    if !orientation.text.isEmpty { Text(orientation.text) }
                } else if !session.config.tagline.isEmpty {
                    Text(session.config.tagline).font(.title3)
                }
                Text("Choose a section on the left to see its pages.").foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The projection of the selected section, over the width of list and page. The page of the selected element opens
/// in a sheet on the right.
private struct ProjectionColumn: View {
    @Bindable var session: WikiSession

    var body: some View {
        ProjectionHost(session: session, mode: session.mode)
            .toolbar {
                ToolbarItemGroup {
                    if let id = session.selectedSection, let section = session.metamodel.sections.first(where: { $0.id == id }) {
                        ModePicker(modes: ProjectionHost.modes(for: section, metamodel: session.metamodel), current: session.mode,
                                   label: { ProjectionHost.label(ofMode: $0, metamodel: session.metamodel) }, choose: { session.select(mode: $0) })
                    }
                    AgreedOnlyToggle(session: session)
                }
            }
            .inspector(isPresented: Binding(get: { session.selectedPage != nil }, set: { if !$0 { session.deselectPage() } })) {
                if let ref = session.selectedPage {
                    VStack(spacing: 0) {
                        HStack {
                            Button("Show in List") { session.select(mode: ListModel.listMode) }
                            Spacer()
                            Button("Close", systemImage: "xmark") { session.deselectPage() }
                                .labelStyle(.iconOnly)
                                .help("Close the page")
                        }
                        .padding(8)
                        Divider()
                        PageColumn(session: session, ref: ref)
                    }
                    .inspectorColumnWidth(min: 320, ideal: 440, max: 720)
                }
            }
    }
}

private struct WikiSessionKey: FocusedValueKey {
    typealias Value = WikiSession
}

extension FocusedValues {
    /// The session of the focused wiki window, for the menu commands.
    public var wikiSession: WikiSession? {
        get { self[WikiSessionKey.self] }
        set { self[WikiSessionKey.self] = newValue }
    }
}
