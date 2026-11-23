import AppKit
import CryptoKit
import WebKit

/// The locked-down web view of one diagram, and how it is loaded and fed.
///
/// - Nothing is loaded from the network: a content rule list blocks every request but the files of the
///   bundled folder, and the navigation delegate cancels every navigation but the page itself.
/// - The web view may read only the bundled folder (`loadFileURL(_:allowingReadAccessTo:)`), never the wiki.
/// - JavaScript cannot open windows, and the data store keeps nothing.
/// - Clicks come back as strings and are checked against the ids of the diagram on show.
@MainActor final class DiagramPage: NSObject {
    /// How a `show` ended.
    enum Outcome: Equatable {
        case drawn
        case failed
        /// A newer `show` replaced this one.
        case superseded
        /// The draw took longer than `renderTimeout`. The page is retired.
        case timedOut
        /// The web content process died. The page is retired.
        case crashed
    }

    let webView: WKWebView
    private let folder: URL
    private let pageURL: URL
    private var known: Set<String> = []
    private var generation = 0
    private var loaded = false
    private var loading: [CheckedContinuation<Bool, Never>] = []
    private var initialLoadAllowed = true
    /// How long one draw, and the first load, may take.
    var renderTimeout = DiagramLimits.renderTimeout
    /// False once the web content process died or a draw timed out. A page that is not alive draws nothing more.
    private(set) var isAlive = true
    /// Called once when the web content process died.
    var onTerminate: (() -> Void)?
    /// Called with the id of a clicked node that the diagram on show has.
    var onSelect: ((String) -> Void)?
    /// Messages that were dropped, and navigations that were cancelled, since the page opened.
    private(set) var droppedMessages = 0
    private(set) var cancelledNavigations = 0
    private(set) var acceptedMessages = 0

    /// The rule lists on hand, by identifier.
    private static var ruleLists: [String: WKContentRuleList] = [:]
    /// All diagram web views of the app share one data store, so they can share a web content process.
    /// The store is non-persistent: it keeps nothing.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()
    /// The identifier of a rule list: a fixed name, a version and a digest of the folder, so the same
    /// installation finds its list again in every launch and a changed rule bumps `rulesVersion`.
    static let rulesVersion = 1

    static func ruleListIdentifier(for folder: URL) -> String {
        let digest = SHA256.hash(data: Data(folder.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "org.systems42.diagram-rules.v\(rulesVersion).\(digest)"
    }

    /// Opens the web view on the bundled page. Nil when the files are missing or the rules do not compile.
    static func open(folder: URL? = DiagramAssets.folder, timeout: Duration = DiagramLimits.renderTimeout) async -> DiagramPage? {
        guard let folder, let rules = await compiledRules(allowing: folder) else { return nil }
        let page = DiagramPage(folder: folder, rules: rules)
        page.renderTimeout = timeout
        return await page.load() ? page : nil
    }

    /// The content rule list that blocks every request but the files of the folder. Looked up first, compiled once.
    static func compiledRules(allowing folder: URL) async -> WKContentRuleList? {
        guard let json = try? DiagramBridge.ruleListJSON(allowing: folder) else { return nil }
        let identifier = ruleListIdentifier(for: folder)
        if let known = ruleLists[identifier] { return known }
        let store = WKContentRuleListStore.default()
        let found = try? await store?.contentRuleList(forIdentifier: identifier)
        // A stored list was compiled from the same folder and version, so it holds the same rules.
        if let found { ruleLists[identifier] = found; return found }
        guard let compiled = try? await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else { return nil }
        ruleLists[identifier] = compiled
        return compiled
    }

    private init(folder: URL, rules: WKContentRuleList) {
        self.folder = folder
        pageURL = folder.appending(path: DiagramAssets.pageName)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.dataStore
        configuration.userContentController.add(rules)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.suppressesIncrementalRendering = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), configuration: configuration)
        super.init()
        configuration.userContentController.add(MessageRelay(page: self), name: DiagramBridge.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    /// Loads the bundled page once. False when it did not load.
    private func load() async -> Bool {
        webView.loadFileURL(pageURL, allowingReadAccessTo: folder)
        let limit = renderTimeout
        let timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: limit)
            if !Task.isCancelled { self?.finishLoading(false) }
        }
        let done = await withCheckedContinuation { loading.append($0) }
        timer.cancel()
        return done
    }

    /// Draws the content. The page learns the diagram as JSON arguments. A newer call supersedes this one.
    /// A draw that takes longer than `renderTimeout` ends with `timedOut` and retires the page.
    func show(_ content: DiagramContent, dark: Bool, frameColours: [String: [String]] = [:]) async -> Outcome {
        generation += 1
        let mine = generation
        known = content.nodeIDs
        guard isAlive else { return .crashed }
        guard loaded, let argument = try? DiagramBridge.argument(for: DiagramBridge.payload(for: content, dark: dark, frameColours: frameColours))
        else { return .failed }
        let result = await raced(argument)
        switch result {
        case .timeout:
            retire()
            return .timedOut
        case .terminated:
            retire()
            return .crashed
        case .failed:
            return mine == generation ? .failed : .superseded
        case .value(let text):
            guard mine == generation else { return .superseded }
            return text == "ok" ? .drawn : .failed
        }
    }

    private enum Raced: Sendable {
        case value(String?), failed, terminated, timeout
    }

    /// Takes the first of two things: the answer of the page, or the end of the time bound.
    private final class Race {
        private var continuation: CheckedContinuation<Raced, Never>?
        var timer: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<Raced, Never>) { self.continuation = continuation }
        func finish(_ result: Raced) {
            timer?.cancel()
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    private func raced(_ argument: Any) async -> Raced {
        let limit = renderTimeout
        let web = webView
        return await withCheckedContinuation { (continuation: CheckedContinuation<Raced, Never>) in
            let race = Race(continuation)
            race.timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                race.finish(.timeout)
            }
            Task { @MainActor in
                do {
                    let value = try await web.callAsyncJavaScript(
                        "return await S42Diagram.render(payload);", arguments: ["payload": argument], in: nil, contentWorld: .page)
                    race.finish(.value(value as? String))
                } catch {
                    // An error of the script is a failed draw. Any other error means the web content is gone.
                    let found = error as NSError
                    // (A dead process answers "result of an unsupported type".)
                    let ofScript = found.domain == WKError.errorDomain && found.code == WKError.javaScriptExceptionOccurred.rawValue
                    race.finish(ofScript ? .failed : .terminated)
                }
            }
        }
    }

    /// The page cannot draw any more: the process died or was too slow. The owner opens a new one.
    private func retire() {
        isAlive = false
        webView.stopLoading()
    }

    /// Forgets the nodes of the diagram on show, so no click is accepted.
    func clear() {
        generation += 1
        known = []
    }

    /// Runs a script the tests give, with arguments. Never used with wiki text.
    func evaluate(_ body: String, arguments: [String: Any] = [:]) async -> Any? {
        try? await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }

    fileprivate func receive(_ body: Any) {
        guard let id = DiagramBridge.validated(body, known: known) else { droppedMessages += 1; return }
        acceptedMessages += 1
        onSelect?(id)
    }

    fileprivate func finishLoading(_ success: Bool) {
        guard !loading.isEmpty else { return }
        loaded = success
        let waiting = loading
        loading = []
        for continuation in waiting { continuation.resume(returning: success) }
    }
}

/// The message handler holds the page weakly: the web view keeps its handlers, so a strong one would be a cycle.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var page: DiagramPage?
    init(page: DiagramPage) { self.page = page }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor [weak page] in page?.receive(body) }
    }
}

extension DiagramPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // The first load of the bundled page is the only navigation. A later one, to the same file too, is cancelled.
        if initialLoadAllowed, DiagramBridge.allowsNavigation(to: action.request.url, page: pageURL) {
            initialLoadAllowed = false
            return .allow
        }
        cancelledNavigations += 1
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isAlive = false
        loaded = false
        finishLoading(false)
        onTerminate?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoading(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoading(false) }
}

extension DiagramPage: WKUIDelegate {
    /// A page script may not open a window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}
