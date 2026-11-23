import AppKit
import SwiftUI
import Systems42Kit
import WebKit

/// What a diagram view is doing. The words of a message are the reader's: plain, no error codes.
enum DiagramState: Equatable {
    case loading
    case drawn
    case message(String)

    static let tooLarge = "This diagram is too large to draw. The pages it names are listed below."
    static let missingFiles = "The diagram files are missing, so the diagram is not drawn."
    static let notDrawn = "This diagram could not be drawn."
    static let tookTooLong = "This diagram took too long to draw."
    static let stopped = "The diagram view stopped working."
    static let busy = "Diagrams are busy. This one is drawn when another has finished. The pages it names are listed below."
    static let evicted = "This diagram was closed to make room for others. The pages it names are listed below."
}

/// The model of one diagram view. It holds a lease of the app's `DiagramBudget`, which holds the web view.
/// Requests supersede each other: only the latest one is drawn, and an older one never sets the state.
@MainActor @Observable final class DiagramViewModel {
    private(set) var state = DiagramState.loading
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var shown: Shown?
    @ObservationIgnored var onSelect: ((String) -> Void)?
    /// The budget of the whole app.
    @ObservationIgnored let budget: DiagramBudget
    @ObservationIgnored private let lease: DiagramBudget.Lease
    /// The bundled folder. Tests give their own, or none.
    @ObservationIgnored private let folder: () -> URL?
    @ObservationIgnored private let timeout: Duration

    private struct Shown: Equatable {
        let content: DiagramContent
        let dark: Bool
        let colours: [String: [String]]
    }

    init(folder: @escaping () -> URL? = { DiagramAssets.folder }, timeout: Duration = DiagramLimits.renderTimeout,
         budget: DiagramBudget = .shared) {
        self.folder = folder
        self.timeout = timeout
        self.budget = budget
        lease = budget.lease()
        lease.onEvicted = { [weak self] in self?.evicted() }
    }

    deinit {
        let budget = budget, lease = lease
        Task { @MainActor in budget.giveBack(lease) }
    }

    /// The page, while the budget keeps one for this view.
    var page: DiagramPage? { lease.page }
    var webView: NSView? { page?.webView }

    /// Gives the page back to the budget. The next `show` gets a new one.
    func close() {
        request += 1
        budget.giveBack(lease)
        shown = nil
        state = .loading
    }

    /// Draws the content. The same content in the same theme is not drawn again. When the budget has no place,
    /// the view says diagrams are busy and draws by itself when its turn comes.
    func show(_ content: DiagramContent, dark: Bool, frameColours: [String: [String]] = [:]) async {
        request += 1
        let mine = request
        if content.tooLarge {
            page?.clear()
            shown = nil
            state = .message(DiagramState.tooLarge)
            return
        }
        let wanted = Shown(content: content, dark: dark, colours: frameColours)
        if wanted == shown, state == .drawn, page?.isAlive == true { return }
        guard let recipe = await DiagramPage.recipe(folder: folder(), timeout: timeout) else {
            if mine == request { state = .message(DiagramState.missingFiles) }
            return
        }
        var retried = false
        while mine == request {
            let outcome = await budget.draw(lease, recipe: recipe, waiting: {
                shown = nil
                state = .message(DiagramState.busy)
            }) { page -> DiagramPage.Outcome in
                guard mine == request else { return .superseded }
                watch(page)
                shown = wanted
                return await page.show(content, dark: dark, frameColours: frameColours)
            }
            guard mine == request, let outcome else { return }
            switch outcome {
            case .drawn: state = .drawn
            case .failed: state = .message(DiagramState.notDrawn)
            case .superseded: return
            case .timedOut:
                shown = nil
                state = .message(DiagramState.tookTooLong)
            case .crashed, .refused:
                shown = nil
                // A process that died is opened again, once.
                if !retried { retried = true; continue }
                state = .message(DiagramState.stopped)
            }
            return
        }
    }

    private func watch(_ page: DiagramPage) {
        page.onSelect = { [weak self] id in self?.onSelect?(id) }
        page.onTerminate = { [weak self, weak page] in
            guard let self, let page, self.page === page else { return }
            shown = nil
            state = .message(DiagramState.stopped)
        }
    }

    /// The budget took the idle page to make room. The view shows the text list and does not draw by itself.
    private func evicted() {
        guard state != .message(DiagramState.busy) else { return }
        shown = nil
        state = .message(DiagramState.evicted)
    }
}

/// Lets the model's web view sit in SwiftUI.
private struct WebViewHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A diagram drawn in the locked-down web view, and every node that opens a page as a text link under it.
/// The text links are the way in for the keyboard and for a screen reader. The web view exists only while
/// the diagram is on screen and the app's budget has a place for it.
public struct DiagramView: View {
    let content: DiagramContent
    let label: String
    /// The text of a link under the diagram, from the node. Built once per node.
    let title: (DiagramContent.Node) -> String
    /// A node was chosen: by a click in the diagram or by its text link.
    let select: (DiagramContent.Node) -> Void
    /// What a reader sees in place of a diagram that is not drawn: the source of a Mermaid block.
    let fallbackText: String?
    /// The frame colours of node types, by id prefix: light and dark `#rrggbb`.
    let frameColours: [String: [String]]
    @State private var model = DiagramViewModel()
    @State private var attempt = 0
    @Environment(\.colorScheme) private var scheme

    /// `onSelect` gets the id of the clicked node.
    public init(_ source: DiagramSource, label: String = "Diagram", onSelect: @escaping (String) -> Void) {
        self.init(DiagramContent(source), label: label, title: { $0.id }, fallbackText: nil, frameColours: [:],
                  select: { onSelect($0.id) })
    }

    init(_ content: DiagramContent, label: String, title: @escaping (DiagramContent.Node) -> String,
         fallbackText: String?, frameColours: [String: [String]] = [:], select: @escaping (DiagramContent.Node) -> Void) {
        self.content = content
        self.label = label
        self.title = title
        self.fallbackText = fallbackText
        self.frameColours = frameColours
        self.select = select
    }

    public var body: some View {
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
        .onDisappear { model.close() }
        .task(id: Run(content: content, dark: scheme == .dark, colours: frameColours, attempt: attempt)) {
            model.onSelect = { id in if let node = content.node(id: id) { select(node) } }
            await model.show(content, dark: scheme == .dark, frameColours: frameColours)
        }
    }

    private struct Run: Equatable {
        let content: DiagramContent
        let dark: Bool
        let colours: [String: [String]]
        let attempt: Int
    }

    @ViewBuilder private var placeholder: some View {
        switch model.state {
        case .loading:
            ProgressView().controlSize(.small)
        case .message(let text):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: text).foregroundStyle(.secondary)
                if text == DiagramState.evicted {
                    Button("Show diagram") { attempt += 1 }
                } else if ![DiagramState.tooLarge, DiagramState.missingFiles, DiagramState.busy].contains(text) {
                    Button("Draw again") { attempt += 1 }
                }
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
    let title: (DiagramContent.Node) -> String
    let select: (DiagramContent.Node) -> Void

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
                        Button { select(node) } label: { Text(verbatim: title(node)) }
                            .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
