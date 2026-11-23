import AppKit
import SwiftUI
import Systems42Kit

/// The right column: the selected page. A new page, or a replaced wiki, makes a new `PageView`.
struct PageColumn: View {
    let session: WikiSession
    let ref: PageRef

    var body: some View {
        PageView(session: session, ref: ref).id(Identity(ref: ref, revision: session.revision))
    }

    private struct Identity: Hashable {
        let ref: PageRef
        let revision: Int
    }
}

struct PageView: View {
    let session: WikiSession
    let ref: PageRef
    @State private var model: PageModel?
    @State private var removed = false

    var body: some View {
        Group {
            if let model {
                PageContent(model: model, session: session, marks: session.search.pageMarks(for: ref))
            } else if removed {
                Text("This page was removed.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task {
            guard let made = PageModel(session: session, ref: ref) else {
                removed = true
                return
            }
            model = made
            await made.load()
        }
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
        .environment(\.pageLinks, links)
        .environment(\.pageMarks, marks)
    }

    private var links: PageLinks {
        PageLinks(
            open: { action in
                switch action {
                case .page(let ref): session.open(.page(ref))
                case .web(let url): NSWorkspace.shared.open(url)
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
