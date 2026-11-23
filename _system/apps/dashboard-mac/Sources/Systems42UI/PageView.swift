import AppKit
import SwiftUI
import Systems42Kit

/// The right column: the selected page. A new page makes a new `PageView`. A replaced wiki does not:
/// the view keeps its content, and its scroll position, until the new content is ready.
struct PageColumn: View {
    let session: WikiSession
    let ref: PageRef

    var body: some View {
        PageView(session: session, ref: ref).id(ref)
    }
}

/// The model of the page view, and how it follows a new revision of the wiki. The model it holds is never
/// nil between two revisions of a page that exists: a new one replaces it when it is ready.
@MainActor @Observable final class PageShown {
    private(set) var model: PageModel?
    private(set) var removed = false
    @ObservationIgnored private let session: WikiSession
    @ObservationIgnored let ref: PageRef

    init(session: WikiSession, ref: PageRef) {
        self.session = session
        self.ref = ref
    }

    /// Brings the shown model in line with the session's revision.
    /// - A page that is gone is shown as removed.
    /// - A page that shows the same as before keeps its model, rebased on the new revision.
    /// - Else the new model replaces the old when its body is rendered. A newer revision that arrives
    ///   meanwhile cancels this and the old content stays.
    func follow() async {
        guard let made = PageModel(session: session, ref: ref) else {
            model = nil
            removed = true
            return
        }
        removed = false
        if let shown = model, shown.isLoaded {
            if shown.fingerprint == made.fingerprint {
                shown.follow(revision: session.revision)
                return
            }
            await made.load()
            guard !Task.isCancelled, made.isLoaded else { return }
            model = made
            return
        }
        // Nothing to keep on screen: show the new model, with its spinner, and render.
        model = made
        await made.load()
    }
}

struct PageView: View {
    let session: WikiSession
    let ref: PageRef
    @State private var shown: PageShown

    init(session: WikiSession, ref: PageRef) {
        self.session = session
        self.ref = ref
        _shown = State(initialValue: PageShown(session: session, ref: ref))
    }

    var body: some View {
        Group {
            if let model = shown.model {
                PageContent(model: model, session: session, marks: session.search.pageMarks(for: ref))
            } else if shown.removed {
                Text("This page was removed.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task(id: session.revision) { await shown.follow() }
    }
}

private struct PageContent: View {
    let model: PageModel
    let session: WikiSession
    let marks: PageMarks
    @Environment(\.explain) private var explain

    /// A comfortable line length for reading.
    private static let readingWidth: CGFloat = 720

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHead(model: model)
                if !model.problems.isEmpty {
                    Text(verbatim: model.problems.joined(separator: " "))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    BlockList(blocks: model.blocks, lazy: true)
                }
                PageDiagram(session: session, ref: model.page.ref)
                Divider()
                RelationsPanel(outgoing: model.outgoing, incoming: model.incoming, definition: model.definition(of:))
                IssuesPanel(issues: model.openIssues)
                SourcesPanel(sources: model.sources)
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: Self.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { PageActionButtons(session: session) }
        .environment(\.pageLinks, links)
        .environment(\.pageMarks, marks)
    }

    private var links: PageLinks {
        PageLinks(
            open: { action in
                switch action {
                case .page(let ref): session.open(.page(ref))
                case .web(let url): OutgoingLinks.openFromContent(url)
                case .anchor(let name): explain(.link(.anchor(name)))
                case .metamodel(let name): explain(.link(.metamodel(name)))
                }
            },
            definition: { action, optionHeld in
                switch action {
                case .anchor(let name):
                    // A click opens the anchor's entry. Option-click shows its definition.
                    guard optionHeld else { return nil }
                    return model.definition(for: .anchor(name)).map { Definition(title: name, text: $0) }
                case .page(let ref):
                    guard optionHeld, let text = model.definition(for: .page(ref)) else { return nil }
                    return Definition(title: session.store.page(ref)?.title ?? ref.stem, text: text)
                case .web, .metamodel:
                    return nil
                }
            }
        )
    }
}
