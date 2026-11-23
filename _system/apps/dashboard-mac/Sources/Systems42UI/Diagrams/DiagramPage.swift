import AppKit
import CryptoKit
import WebKit

/// The locked-down web view of one diagram, and how it is loaded and fed. Only a `DiagramBudget` makes one
/// (the initializer needs a `PageMeter`), and every script the page runs is reported to that budget.
///
/// - Nothing is loaded from the network: a content rule list blocks every request but the files of the
///   bundled folder, and the navigation delegate cancels every navigation but the page itself.
/// - The web view may read only the bundled folder (`loadFileURL(_:allowingReadAccessTo:)`), never the wiki.
/// - JavaScript cannot open windows, and the data store keeps nothing.
/// - Clicks come back as strings and are checked against the ids of the diagram on show.
@MainActor final class DiagramPage: NSObject, BudgetedPage {
    /// How a `show` ended.
    enum Outcome: Equatable {
        case drawn
        case failed
        /// A newer `show` replaced this one.
        case superseded
        /// The draw took longer than its bound. The page draws nothing more.
        case timedOut
        /// The web content process died, or the page was destroyed.
        case crashed
        /// The budget did not let the page run a script.
        case refused
    }

    /// What a page is made from: the bundled folder, its compiled rules, and the bound of one draw.
    struct Recipe {
        let folder: URL
        let rules: WKContentRuleList
        let timeout: Duration
    }

    /// The web view, until the budget destroys the page.
    private(set) var webView: WKWebView?
    private let meter: PageMeter
    private let folder: URL
    private let pageURL: URL
    private var known: Set<String> = []
    private var generation = 0
    private var loaded = false
    private var loadStarted = false
    private var loadEnded = false
    private var loadTimedOut = false
    private var loading: [CheckedContinuation<Load, Never>] = []
    private var initialLoadAllowed = true
    /// How long one draw may take. The first load has the standard bound.
    let renderTimeout: Duration
    /// False once the process died, a script did not answer in time, or the page was destroyed.
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
    /// All diagram web views of the app share one data store. The store is non-persistent: it keeps nothing.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()
    /// The identifier of a rule list: a fixed name and a digest of the rules themselves, so a list that is
    /// found by this name holds exactly these rules. Rules that change get a new name, and no old list is reused.
    static func ruleListIdentifier(forRules json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return "org.systems42.diagram-rules.\(digest)"
    }

    /// The recipe of a page on the bundled folder. Nil when the files are missing or the rules do not compile.
    static func recipe(folder: URL? = DiagramAssets.folder, timeout: Duration = DiagramLimits.renderTimeout) async -> Recipe? {
        guard let folder, let rules = await compiledRules(allowing: folder) else { return nil }
        return Recipe(folder: folder, rules: rules, timeout: timeout)
    }

    /// The content rule list that blocks every request but the files of the folder. Looked up first, compiled once.
    static func compiledRules(allowing folder: URL) async -> WKContentRuleList? {
        guard let json = try? DiagramBridge.ruleListJSON(allowing: folder) else { return nil }
        let identifier = ruleListIdentifier(forRules: json)
        if let known = ruleLists[identifier] { return known }
        let store = WKContentRuleListStore.default()
        let found = try? await store?.contentRuleList(forIdentifier: identifier)
        // The name holds a digest of the rules, so a stored list under it holds these rules.
        if let found { ruleLists[identifier] = found; return found }
        guard let compiled = try? await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else { return nil }
        ruleLists[identifier] = compiled
        return compiled
    }

    /// Made by the budget only: nothing else has a meter.
    init(meter: PageMeter, recipe: Recipe) {
        self.meter = meter
        folder = recipe.folder
        renderTimeout = recipe.timeout
        pageURL = recipe.folder.appending(path: DiagramAssets.pageName)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.dataStore
        configuration.userContentController.add(recipe.rules)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.suppressesIncrementalRendering = false
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), configuration: configuration)
        webView = web
        super.init()
        configuration.userContentController.add(MessageRelay(page: self), name: DiagramBridge.handlerName)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
    }

    fileprivate enum Load { case loaded, failed, timedOut }

    /// Whether the bundled page has loaded.
    var isLoaded: Bool { loaded }

    /// Loads the bundled page once, as one script the budget counts. Shows that come during the load wait for it.
    func prepare() async -> Bool {
        if loaded { return true }
        guard isAlive, !loadEnded, let webView else { return false }
        if !loadStarted {
            guard meter.start() else { return false }
            loadStarted = true
            webView.loadFileURL(pageURL, allowingReadAccessTo: folder)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: DiagramLimits.renderTimeout)
                self?.finishLoading(.timedOut)
            }
        }
        return await withCheckedContinuation { loading.append($0) } == .loaded
    }

    /// Draws the content. The page learns the diagram as JSON arguments. A newer call supersedes this one.
    /// A draw that takes longer than `renderTimeout` ends with `timedOut`, and the page draws nothing more.
    func show(_ content: DiagramContent, dark: Bool, frameColours: [String: [String]] = [:]) async -> Outcome {
        generation += 1
        let mine = generation
        known = content.nodeIDs
        guard isAlive else { return .crashed }
        guard await prepare() else { return isAlive ? .refused : (loadTimedOut ? .timedOut : .crashed) }
        guard mine == generation else { return .superseded }
        guard let argument = try? DiagramBridge.argument(for: DiagramBridge.payload(for: content, dark: dark, frameColours: frameColours))
        else { return .failed }
        switch await raced("return await S42Diagram.render(payload);", arguments: ["payload": argument], limit: renderTimeout) {
        case .refused: return isAlive ? .refused : .crashed
        case .timeout: return .timedOut
        case .terminated: return .crashed
        case .failed: return mine == generation ? .failed : .superseded
        case .value(let text):
            guard mine == generation else { return .superseded }
            return text == "ok" ? .drawn : .failed
        }
    }

    private enum Raced: Sendable {
        case value(String?), failed, terminated, timeout, refused
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

    /// Runs a script and takes the first of two things: its answer (a string), or the end of the time bound.
    /// The budget is told when the script starts and how it ended. A script that did not answer in time may
    /// still run: the page draws nothing more, and the budget keeps it counted.
    private func raced(_ script: String, arguments: [String: Any], limit: Duration) async -> Raced {
        guard isAlive, let web = webView, meter.start() else { return .refused }
        let started = ContinuousClock.now
        var result = await withCheckedContinuation { (continuation: CheckedContinuation<Raced, Never>) in
            let race = Race(continuation)
            race.timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                race.finish(.timeout)
            }
            web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    race.finish(.value(value as? String))
                case .failure(let error):
                    // An error of the script is a failed draw. Any other error means the web content is gone.
                    // (A dead process answers "result of an unsupported type".)
                    let found = error as NSError
                    let ofScript = found.domain == WKError.errorDomain && found.code == WKError.javaScriptExceptionOccurred.rawValue
                    race.finish(ofScript ? .failed : .terminated)
                }
            }
        }
        // An answer that came after the bound is late too: the timer can lose the race on a busy main thread.
        if ContinuousClock.now - started > limit, case .value = result { result = .timeout }
        if ContinuousClock.now - started > limit, case .failed = result { result = .timeout }
        switch result {
        case .value, .failed: meter.answered()
        case .terminated: isAlive = false; meter.gone()
        case .timeout: isAlive = false; meter.noAnswer()
        case .refused: break
        }
        return result
    }

    /// A trivial script, for the budget. It answers only when no script of the page is stuck.
    func ping(_ done: @escaping @MainActor @Sendable () -> Void) {
        guard let webView else { done(); return }
        webView.evaluateJavaScript("1") { _, _ in done() }
    }

    /// Called by the budget only. Closes the web view and lets it go.
    func destroy() {
        isAlive = false
        known = []
        finishLoading(.failed)
        guard let web = webView else { return }
        webView = nil
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.configuration.userContentController.removeAllScriptMessageHandlers()
        web.removeFromSuperview()
    }

    /// Forgets the nodes of the diagram on show, so no click is accepted.
    func clear() {
        generation += 1
        known = []
    }

    /// Runs a script the tests give, with arguments. Never used with wiki text.
    /// The answer is read back as JSON. The wait is bounded.
    func evaluate(_ body: String, arguments: [String: Any] = [:], limit: Duration = .seconds(30)) async -> Any? {
        guard await prepare() else { return nil }
        let wrapped = "const answer = await (async () => { \(body)\n })(); return JSON.stringify(answer === undefined ? null : answer);"
        guard case .value(let text?) = await raced(wrapped, arguments: arguments, limit: limit),
              let data = text.data(using: .utf8) else { return nil }
        let answer = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return answer is NSNull ? nil : answer
    }

    fileprivate func receive(_ body: Any) {
        guard let id = DiagramBridge.validated(body, known: known) else { droppedMessages += 1; return }
        acceptedMessages += 1
        onSelect?(id)
    }

    /// Ends the load, once: tells the budget how it ended and wakes every show that waits for it.
    fileprivate func finishLoading(_ result: Load) {
        guard loadStarted, !loaded, !loadEnded else { return }
        loadEnded = true
        loaded = result == .loaded
        switch result {
        case .loaded: meter.answered()
        case .failed: isAlive = false; meter.gone()
        case .timedOut: isAlive = false; loadTimedOut = true; meter.noAnswer()
        }
        let waiting = loading
        loading = []
        for continuation in waiting { continuation.resume(returning: result) }
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

    /// The process is gone: the owner learns it first, then the budget, which destroys the page.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isAlive = false
        finishLoading(.failed)
        onTerminate?()
        meter.gone()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading(.loaded) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoading(.failed) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoading(.failed) }
}

extension DiagramPage: WKUIDelegate {
    /// A page script may not open a window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}
