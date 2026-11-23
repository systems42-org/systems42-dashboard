import AppKit
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
    }

    let webView: WKWebView
    private let folder: URL
    private let pageURL: URL
    private var known: Set<String> = []
    private var generation = 0
    private var loaded = false
    private var loading: [CheckedContinuation<Bool, Never>] = []
    private var navigationFailed = false
    /// Called with the id of a clicked node that the diagram on show has.
    var onSelect: ((String) -> Void)?
    /// Messages that were dropped, and navigations that were cancelled, since the page opened.
    private(set) var droppedMessages = 0
    private(set) var cancelledNavigations = 0
    private(set) var acceptedMessages = 0

    /// The rule lists that were compiled, by identifier.
    private static var ruleLists: [String: WKContentRuleList] = [:]

    /// Opens the web view on the bundled page. Nil when the files are missing or the rules do not compile.
    static func open(folder: URL? = DiagramAssets.folder) async -> DiagramPage? {
        guard let folder, let rules = await compiledRules(allowing: folder) else { return nil }
        let page = DiagramPage(folder: folder, rules: rules)
        return await page.load() ? page : nil
    }

    /// The content rule list that blocks every request but the files of the folder.
    static func compiledRules(allowing folder: URL) async -> WKContentRuleList? {
        guard let json = try? DiagramBridge.ruleListJSON(allowing: folder) else { return nil }
        let identifier = "s42-diagram-" + String(abs(folder.path.hashValue), radix: 16) + "-" + String(json.utf8.count)
        if let known = ruleLists[identifier] { return known }
        guard let compiled = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
        else { return nil }
        ruleLists[identifier] = compiled
        return compiled
    }

    private init(folder: URL, rules: WKContentRuleList) {
        self.folder = folder
        pageURL = folder.appending(path: DiagramAssets.pageName)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
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
        return await withCheckedContinuation { loading.append($0) }
    }

    /// Draws the content. The page learns the diagram as JSON arguments. A newer call supersedes this one.
    func show(_ content: DiagramContent, dark: Bool) async -> Outcome {
        generation += 1
        let mine = generation
        known = content.nodeIDs
        guard loaded, let argument = try? DiagramBridge.argument(for: DiagramBridge.payload(for: content, dark: dark)) else { return .failed }
        let result = try? await webView.callAsyncJavaScript(
            "return await S42Diagram.render(payload);", arguments: ["payload": argument], in: nil, contentWorld: .page)
        guard mine == generation else { return .superseded }
        return (result as? String) == "ok" ? .drawn : .failed
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
        if DiagramBridge.allowsNavigation(to: action.request.url, page: pageURL) { return .allow }
        cancelledNavigations += 1
        return .cancel
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
