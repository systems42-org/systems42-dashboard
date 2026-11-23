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
    static let tookTooLong = "This diagram took too long to draw."
    static let stopped = "The diagram view stopped working."
}

/// The model of one diagram view: it owns the web view and feeds it. Requests supersede each other: only
/// the latest one is drawn, and an older one never sets the state.
@MainActor @Observable final class DiagramViewModel {
    private(set) var state = DiagramState.loading
    @ObservationIgnored private(set) var page: DiagramPage?
    @ObservationIgnored private var opening: Task<DiagramPage?, Never>?
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var shown: Shown?
    @ObservationIgnored var onSelect: ((String) -> Void)?
    /// Opens the web view. Tests give their own folder, or none.
    @ObservationIgnored private let folder: () -> URL?
    @ObservationIgnored private let timeout: Duration

    private struct Shown: Equatable {
        let content: DiagramContent
        let dark: Bool
        let colours: [String: [String]]
    }

    init(folder: @escaping () -> URL? = { DiagramAssets.folder }, timeout: Duration = DiagramLimits.renderTimeout) {
        self.folder = folder
        self.timeout = timeout
    }

    var webView: NSView? { page?.webView }

    /// Gives the web view back. The next `show` opens a new one.
    func close() {
        request += 1
        opening?.cancel()
        opening = nil
        page = nil
        shown = nil
        state = .loading
    }

    /// Draws the content. The same content in the same theme is not drawn again.
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
        var retried = false
        while true {
            guard let page = await ensurePage() else {
                if mine == request { state = .message(DiagramState.missingFiles) }
                return
            }
            guard mine == request else { return }
            shown = wanted
            let outcome = await page.show(content, dark: dark, frameColours: frameColours)
            guard mine == request else { return }
            switch outcome {
            case .drawn: state = .drawn
            case .failed: state = .message(DiagramState.notDrawn)
            case .superseded: return
            case .timedOut:
                discard(page)
                state = .message(DiagramState.tookTooLong)
            case .crashed:
                discard(page)
                // A process that died is opened again, once.
                if !retried { retried = true; continue }
                state = .message(DiagramState.stopped)
            }
            return
        }
    }

    private func discard(_ dead: DiagramPage) {
        if page === dead { page = nil }
        shown = nil
    }

    /// The live page, opened when there is none. Requests that come while it opens share one open.
    private func ensurePage() async -> DiagramPage? {
        if let page, page.isAlive { return page }
        page = nil
        let task: Task<DiagramPage?, Never>
        if let opening {
            task = opening
        } else {
            let folder = folder(), timeout = timeout
            task = Task { await DiagramPage.open(folder: folder, timeout: timeout) }
            opening = task
        }
        let opened = await task.value
        guard opening == task else { return page }
        opening = nil
        guard let opened else { return nil }
        opened.onSelect = { [weak self] id in self?.onSelect?(id) }
        opened.onTerminate = { [weak self, weak opened] in
            guard let self, self.page === opened else { return }
            self.page = nil
            self.shown = nil
            self.state = .message(DiagramState.stopped)
        }
        page = opened
        return opened
    }
}

/// How many web views live at once in a window. A web view is a process that loads 3.5 MB of script,
/// so a view that is on screen asks for a place, and one that gets none shows a placeholder.
@MainActor final class DiagramBudget {
    static let shared = DiagramBudget()
    let limit: Int
    private var holders: [DiagramSlot] = []

    init(limit: Int = DiagramLimits.mostLiveViews) {
        self.limit = limit
    }

    var liveCount: Int { holders.count }

    /// Takes a place when one is free.
    func acquire(_ slot: DiagramSlot) -> Bool {
        if holders.contains(where: { $0 === slot }) { return true }
        guard holders.count < limit else { return false }
        holders.append(slot)
        slot.isLive = true
        return true
    }

    /// Takes a place, from the view that has had one longest when none is free.
    func claim(_ slot: DiagramSlot) {
        if holders.contains(where: { $0 === slot }) { return }
        if holders.count >= limit, !holders.isEmpty { holders.removeFirst().isLive = false }
        _ = acquire(slot)
    }

    func release(_ slot: DiagramSlot) {
        holders.removeAll { $0 === slot }
        slot.isLive = false
    }
}

/// The place of one diagram view in the budget.
@MainActor @Observable final class DiagramSlot {
    var isLive = false
}

private struct DiagramBudgetKey: EnvironmentKey {
    static let defaultValue: DiagramBudget? = nil
}

extension EnvironmentValues {
    /// The budget of the window the view is in.
    var diagramBudget: DiagramBudget? {
        get { self[DiagramBudgetKey.self] }
        set { self[DiagramBudgetKey.self] = newValue }
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
/// the diagram is on screen and has a place in the window's budget.
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
    @State private var slot = DiagramSlot()
    @State private var attempt = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.diagramBudget) private var windowBudget

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

    private var budget: DiagramBudget { windowBudget ?? .shared }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if slot.isLive, let web = model.webView, model.state == .drawn {
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
        .onAppear { _ = budget.acquire(slot) }
        .onDisappear {
            budget.release(slot)
            model.close()
        }
        .onChange(of: slot.isLive) { _, live in if !live { model.close() } }
        .task(id: Run(content: content, dark: scheme == .dark, colours: frameColours, attempt: attempt, live: slot.isLive)) {
            guard slot.isLive else { return }
            model.onSelect = { id in if let node = content.node(id: id) { select(node) } }
            await model.show(content, dark: scheme == .dark, frameColours: frameColours)
        }
    }

    private struct Run: Equatable {
        let content: DiagramContent
        let dark: Bool
        let colours: [String: [String]]
        let attempt: Int
        let live: Bool
    }

    @ViewBuilder private var placeholder: some View {
        if !slot.isLive {
            VStack(alignment: .leading, spacing: 6) {
                Button("Show diagram") { budget.claim(slot) }
                if let fallbackText {
                    Text(verbatim: fallbackText).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
        } else {
            switch model.state {
            case .loading:
                ProgressView().controlSize(.small)
            case .message(let text):
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: text).foregroundStyle(.secondary)
                    if text != DiagramState.tooLarge && text != DiagramState.missingFiles {
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
