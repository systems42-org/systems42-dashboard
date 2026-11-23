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
    /// The budget of the whole app. A web view counts against it while it draws, and a given-up one until it answers.
    @ObservationIgnored let budget: DiagramBudget
    @ObservationIgnored private var seat: DiagramBudget.Seat?
    /// Opens the web view. Tests give their own folder, or none.
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
    }

    var webView: NSView? { page?.webView }

    /// Gives the web view back. The next `show` opens a new one.
    func close() {
        request += 1
        releaseSeat()
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
            // No place in the budget: the text list stays, and the diagram waits for a free place.
            guard takeSeat() else {
                page = nil
                shown = nil
                state = .message(DiagramState.busy)
                return
            }
            guard let page = await ensurePage() else {
                releaseSeat()
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
                releaseSeat()
                discard(page)
                // A process that died is opened again, once.
                if !retried { retried = true; continue }
                state = .message(DiagramState.stopped)
            }
            return
        }
    }

    private func takeSeat() -> Bool {
        if seat != nil { return true }
        seat = budget.acquire()
        return seat != nil
    }

    private func releaseSeat() {
        if let seat { budget.release(seat) }
        seat = nil
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
        // A draw that took too long leaves a busy process: its seat stays counted until the web view answers.
        opened.onRetire = { [weak self] web in
            guard let self, let seat = self.seat else { return }
            self.budget.retire(seat, view: web)
            self.seat = nil
        }
        opened.onTerminate = { [weak self, weak opened] in
            guard let self, self.page === opened else { return }
            self.releaseSeat()
            self.page = nil
            self.shown = nil
            self.state = .message(DiagramState.stopped)
        }
        page = opened
        return opened
    }
}

/// The web processes of all diagram views of the app, in every window. A web view is a process that loads
/// 3.5 MB of script, and WebKit has no public way to stop a script that never ends. So the number of
/// processes that are drawing or busy is bounded here, whatever the input is: `DiagramLimits.mostWebProcesses`.
///
/// A view that draws holds a seat. A draw that took too long gives up its web view, which may stay busy:
/// the seat stays counted for as long as the web view does not answer a trivial script, or its process is gone.
@MainActor @Observable final class DiagramBudget {
    /// The budget of the whole app.
    static let shared = DiagramBudget()
    let limit: Int

    /// A place for one web view. Held by identity.
    @MainActor final class Seat {}

    private var seats: [Seat] = []
    private var retired: [Retired] = []
    @ObservationIgnored private var watching: Task<Void, Never>?

    @MainActor private final class Retired {
        let seat: Seat
        let view: WKWebView
        var probing = false
        var answered = false
        init(seat: Seat, view: WKWebView) { self.seat = seat; self.view = view }
    }

    init(limit: Int = DiagramLimits.mostWebProcesses) {
        self.limit = limit
    }

    /// The places in use: drawing views and given-up views that have not answered.
    var inUse: Int { seats.count + retired.count }
    var isFull: Bool { inUse >= limit }
    /// The given-up web views that have not answered.
    var busyCount: Int { retired.count }

    /// A place, or nil when every place is in use.
    func acquire() -> Seat? {
        guard !isFull else { return nil }
        let seat = Seat()
        seats.append(seat)
        return seat
    }

    func release(_ seat: Seat) {
        seats.removeAll { $0 === seat }
    }

    /// The seat's web view is given up. The place stays in use until the view answers or its process is gone.
    func retire(_ seat: Seat, view: WKWebView) {
        seats.removeAll { $0 === seat }
        retired.append(Retired(seat: seat, view: view))
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while true {
                // `self` is held only for the call, never across the sleep.
                guard let more = self?.watch(), more else { self?.watching = nil; return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Asks each given-up web view for a trivial answer, and frees the places of the ones that gave it
    /// (also with an error: the process is gone). True while some remain.
    private func watch() -> Bool {
        for item in retired where !item.probing {
            item.probing = true
            item.view.evaluateJavaScript("1") { _, _ in item.answered = true }
        }
        retired.removeAll { $0.answered }
        return !retired.isEmpty
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
        .task(id: Run(content: content, dark: scheme == .dark, colours: frameColours, attempt: attempt, free: !model.budget.isFull)) {
            model.onSelect = { id in if let node = content.node(id: id) { select(node) } }
            await model.show(content, dark: scheme == .dark, frameColours: frameColours)
        }
    }

    private struct Run: Equatable {
        let content: DiagramContent
        let dark: Bool
        let colours: [String: [String]]
        let attempt: Int
        /// A place is free. A diagram that waited for one is drawn when this turns true.
        let free: Bool
    }

    @ViewBuilder private var placeholder: some View {
        switch model.state {
        case .loading:
            ProgressView().controlSize(.small)
        case .message(let text):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: text).foregroundStyle(.secondary)
                if text != DiagramState.tooLarge && text != DiagramState.missingFiles {
                    Button("Draw again") { attempt += 1 }
                        .disabled(model.budget.isFull)
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
