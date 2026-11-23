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

    public var body: some View {
        VStack(spacing: 0) {
            VersionNoticeLine(session: session)
            NavigationSplitView {
                Sidebar(session: session)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            } content: {
                ListColumn(session: session, storedStates: $storedListStates)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 480)
            } detail: {
                PagePlaceholder(session: session)
            }
            TourPanel(tour: session.tour)
        }
        .overlay(alignment: .topTrailing) { SuggestionList(model: session.search) }
        .toolbar { ToolbarItem { SearchField(model: session.search) } }
        .focusedSceneValue(\.wikiSearch, session.search)
        .onChange(of: session.shownSearch) { _, _ in session.search.followSession() }
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
        }
        .onChange(of: session.selectedSection) { _, id in storedSection = id ?? "" }
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
