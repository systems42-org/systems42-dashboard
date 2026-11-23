import AppKit
import SwiftUI
import Systems42Kit

/// What a diagram view is doing. The words of a message are the reader's: plain, no error codes.
enum DiagramState: Equatable {
    case loading
    case drawn
    case message(String)

    static let tooLarge = "This diagram is too large to draw. The pages it names are listed below."
    static let missingFiles = "The diagram files are missing, so the diagram is not drawn."
    static let notDrawn = "This diagram could not be drawn."
}

/// The model of one diagram view: it owns the web view and feeds it. Only the view and the session of
/// the window know about it, so it holds no session.
@MainActor @Observable final class DiagramViewModel {
    private(set) var state = DiagramState.loading
    @ObservationIgnored private var page: DiagramPage?
    @ObservationIgnored private var opened = false
    @ObservationIgnored private var shown: Shown?
    @ObservationIgnored var onSelect: ((String) -> Void)?
    /// Opens the web view. Tests give their own folder, or none.
    @ObservationIgnored private let folder: () -> URL?

    private struct Shown: Equatable {
        let content: DiagramContent
        let dark: Bool
    }

    init(folder: @escaping () -> URL? = { DiagramAssets.folder }) {
        self.folder = folder
    }

    var webView: NSView? { page?.webView }

    /// Draws the content. The same content in the same theme is not drawn again.
    func show(_ content: DiagramContent, dark: Bool) async {
        if content.tooLarge {
            page?.clear()
            shown = nil
            state = .message(DiagramState.tooLarge)
            return
        }
        let wanted = Shown(content: content, dark: dark)
        if wanted == shown, state == .drawn { return }
        if page == nil, !opened {
            opened = true
            page = await DiagramPage.open(folder: folder())
            page?.onSelect = { [weak self] id in self?.onSelect?(id) }
        }
        guard let page else {
            state = .message(DiagramState.missingFiles)
            return
        }
        shown = wanted
        switch await page.show(content, dark: dark) {
        case .drawn: state = .drawn
        case .failed: state = .message(DiagramState.notDrawn)
        case .superseded: break
        }
    }
}

/// Lets the model's web view sit in SwiftUI.
private struct WebViewHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A diagram drawn in the locked-down web view, and every node that opens a page as a text link under it.
/// The text links are the way in for the keyboard and for a screen reader.
public struct DiagramView: View {
    let source: DiagramSource
    let label: String
    let allowsLinks: Bool
    /// The text of a link under the diagram, from the node. The default is the node id.
    let title: (String) -> String
    /// A node was chosen: by a click in the diagram or by its text link.
    let select: (String) -> Void
    /// What a reader sees in place of a diagram that is not drawn: the source of a Mermaid block.
    let fallbackText: String?
    @State private var model = DiagramViewModel()
    @Environment(\.colorScheme) private var scheme

    /// `onSelect` gets the id of the clicked node.
    public init(_ source: DiagramSource, label: String = "Diagram", onSelect: @escaping (String) -> Void) {
        self.init(source, label: label, allowsLinks: true, title: { $0 }, fallbackText: nil, select: onSelect)
    }

    init(_ source: DiagramSource, label: String, allowsLinks: Bool, title: @escaping (String) -> String,
         fallbackText: String?, select: @escaping (String) -> Void) {
        self.source = source
        self.label = label
        self.allowsLinks = allowsLinks
        self.title = title
        self.fallbackText = fallbackText
        self.select = select
    }

    private var content: DiagramContent { DiagramContent(source, allowsLinks: allowsLinks) }

    public var body: some View {
        let content = content
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let web = model.webView, model.state == .drawn {
                    WebViewHost(view: web)
                        .accessibilityElement()
                        .accessibilityLabel(label)
                        .accessibilityAddTraits(.isImage)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, idealHeight: 360)
            DiagramLinkList(nodes: content.nodes, title: title, select: select)
        }
        .task(id: Run(content: content, dark: scheme == .dark)) {
            model.onSelect = select
            await model.show(content, dark: scheme == .dark)
        }
    }

    private struct Run: Equatable {
        let content: DiagramContent
        let dark: Bool
    }

    @ViewBuilder private var placeholder: some View {
        switch model.state {
        case .loading:
            ProgressView().controlSize(.small)
        case .message(let text):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: text).foregroundStyle(.secondary)
                if let fallbackText {
                    Text(verbatim: fallbackText).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
        case .drawn:
            Color.clear
        }
    }
}

/// Every node that opens a page, as a link.
struct DiagramLinkList: View {
    let nodes: [DiagramContent.Node]
    let title: (String) -> String
    let select: (String) -> Void

    /// One link per page, in the order of the diagram.
    private var listed: [DiagramContent.Node] {
        var seen = Set<String>()
        return nodes.filter { seen.insert($0.ref.map { "\($0.folder)/\($0.stem)" } ?? "node:" + $0.id).inserted }
    }

    var body: some View {
        let listed = listed
        if !listed.isEmpty {
            DisclosureGroup("Pages in this diagram (\(listed.count))") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(listed, id: \.id) { node in
                        Button { select(node.id) } label: { Text(verbatim: title(node.id)) }
                            .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
