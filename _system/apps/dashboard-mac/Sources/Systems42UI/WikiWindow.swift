import SwiftUI
import Systems42Kit

/// One window per wiki: sections, list, page. List and page are placeholders for now.
public struct WikiWindow: View {
    @Bindable var session: WikiSession
    @SceneStorage("selectedSection") private var storedSection = ""

    init(session: WikiSession) {
        self.session = session
    }

    public var body: some View {
        NavigationSplitView {
            Sidebar(session: session)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } content: {
            ListPlaceholder(session: session)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 480)
        } detail: {
            PagePlaceholder(session: session)
        }
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

private struct ListPlaceholder: View {
    let session: WikiSession

    var body: some View {
        if let id = session.selectedSection, let section = session.metamodel.sections.first(where: { $0.id == id }) {
            Text("The pages of \(section.title) will be listed here.").foregroundStyle(.secondary).padding()
        } else {
            Text("Choose a section.").foregroundStyle(.secondary)
        }
    }
}

private struct PagePlaceholder: View {
    let session: WikiSession

    var body: some View {
        if let ref = session.selectedPage {
            Text(ref.stem).foregroundStyle(.secondary)
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
