import AppKit
import Foundation
import Testing
import WebKit
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

private let limit: Duration = .seconds(30)

@MainActor private func until(_ what: String, _ condition: () -> Bool) async {
    let started = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - started > limit { Issue.record("timed out waiting for \(what)"); return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// Waits for a web view to finish loading.
@MainActor private final class Loaded: NSObject, WKNavigationDelegate {
    private(set) var done = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done = true }
}

private func flow(_ label: String) -> DiagramContent {
    DiagramContent(.mermaid("flowchart TB\n  A[\"\(label)\"] --> B[\"other\"]"))
}

/// The process id of the web content process, when this macOS has the key. WebKit has no public call for it.
@MainActor private func processID(of web: WKWebView) -> Int32? {
    guard web.responds(to: NSSelectorFromString("_webProcessIdentifier")) else { return nil }
    return (web.value(forKey: "_webProcessIdentifier") as? Int32).flatMap { $0 > 1 ? $0 : nil }
}

/// Kills the web content process of a web view, as a crash does.
@MainActor private func kill(_ page: DiagramPage) {
    if let pid = processID(of: page.webView) {
        Darwin.kill(pid, SIGKILL)
    } else {
        Issue.record("this macOS has no _webProcessIdentifier, the test cannot kill the process")
    }
}

private func isGone(_ pid: Int32) -> Bool {
    Darwin.kill(pid, 0) != 0 && errno == ESRCH
}

/// A chain of 400 boxes: the layout takes far longer than a millisecond.
private let slowToDraw = DiagramContent(.mermaid("flowchart TB\n" + (0..<400).map { "  N\($0) --> N\($0 + 1)" }.joined(separator: "\n")))

private func nested(_ depth: Int) -> String {
    var text = "flowchart TB\n"
    for n in 0..<depth { text += "subgraph s\(n)\n" }
    return text + "A\n" + String(repeating: "end\n", count: depth)
}

@MainActor private func drawnText(_ page: DiagramPage?) async -> String {
    await page?.evaluate("return document.documentElement.textContent") as? String ?? ""
}

@MainActor private final class WeakView {
    weak var view: WKWebView?
    init(_ view: WKWebView) { self.view = view }
}

@MainActor @Suite struct DiagramRobustnessTests {
    // MARK: A dead or slow web process

    @Test func aDeadProcessLeavesLoadingAndALaterShowDraws() async throws {
        let model = DiagramViewModel(timeout: .seconds(5), budget: DiagramBudget())
        await model.show(flow("FIRST"), dark: false)
        #expect(model.state == .drawn)
        let old = try #require(model.page)
        kill(old)
        await until("the death to show") { model.state != .drawn }
        #expect(model.state == .message(DiagramState.stopped))
        #expect(model.page == nil)
        await model.show(flow("SECOND"), dark: false)
        #expect(model.state == .drawn)
        #expect(model.page !== old)
        #expect(await drawnText(model.page).contains("SECOND"))
    }

    @Test func aShowOnADeadPageEndsWithinTheBound() async throws {
        let page = try #require(await DiagramPage.open(timeout: .seconds(3)))
        kill(page)
        let started = ContinuousClock.now
        let outcome = await page.show(flow("X"), dark: false)
        #expect(outcome == .crashed || outcome == .timedOut, Comment(rawValue: "\(outcome)"))
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(!page.isAlive)
        #expect(await page.show(flow("Y"), dark: false) == .crashed)
    }

    @Test func aRenderThatTakesTooLongEndsWithAMessage() async throws {
        // A bound no draw can meet: the page is retired and the message says why.
        let model = DiagramViewModel(timeout: .milliseconds(1), budget: DiagramBudget())
        await model.show(slowToDraw, dark: false)
        #expect(model.state == .message(DiagramState.tookTooLong))
        #expect(model.page == nil)
        // The next show opens a new page.
        let again = DiagramViewModel(timeout: .seconds(10), budget: DiagramBudget())
        await again.show(flow("FAST"), dark: false)
        #expect(again.state == .drawn)
    }

    @Test func deeplyNestedSubgraphsAreRefusedBeforeTheyHangAProcess() {
        // 400 nested levels took 3 s in Mermaid, 1,200 took 13 s, 2,500 ran for minutes: a draw that cannot be stopped.
        for depth in [DiagramLimits.mostNestingDepth + 1, 400, 1_200, 2_500] {
            #expect(DiagramContent(.mermaid(nested(depth))).tooLarge, "\(depth)")
        }
        #expect(!DiagramContent(.mermaid(nested(DiagramLimits.mostNestingDepth))).tooLarge)
        // Flat subgraphs are not nesting, and `end` words in other places do not count.
        let flat = "flowchart TB\n" + String(repeating: "subgraph a\nA\nend\n", count: 100)
        #expect(!DiagramContent(.mermaid(flat)).tooLarge)
    }

    // MARK: Requests supersede each other

    @Test func theLatestOfTwoRequestsIsDrawn() async throws {
        let model = DiagramViewModel(budget: DiagramBudget())
        let old = Task { await model.show(flow("OLDLABEL"), dark: false) }
        try await Task.sleep(for: .milliseconds(5))
        let new = Task { await model.show(flow("NEWLABEL"), dark: false) }
        await old.value
        await new.value
        #expect(model.state == .drawn)
        let text = await drawnText(model.page)
        #expect(text.contains("NEWLABEL") && !text.contains("OLDLABEL"))
    }

    @Test func theLatestOfFiveRequestsIsDrawn() async throws {
        let model = DiagramViewModel(budget: DiagramBudget())
        var tasks: [Task<Void, Never>] = []
        for n in 0..<5 {
            tasks.append(Task { await model.show(flow("LABEL\(n)X"), dark: false) })
            try await Task.sleep(for: .milliseconds(3))
        }
        for task in tasks { await task.value }
        #expect(model.state == .drawn)
        let text = await drawnText(model.page)
        #expect(text.contains("LABEL4X"))
        for n in 0..<4 { #expect(!text.contains("LABEL\(n)X")) }
    }

    @Test func aThemeChangeDuringTheFirstLoadWins() async throws {
        let model = DiagramViewModel(budget: DiagramBudget())
        let light = Task { await model.show(flow("THEME"), dark: false) }
        let dark = Task { await model.show(flow("THEME"), dark: true) }
        await light.value
        await dark.value
        #expect(model.state == .drawn)
        #expect(await model.page?.evaluate("return document.documentElement.getAttribute('data-theme')") as? String == "dark")
    }

    @Test func filesAreMissingOnlyWhenTheyAre() async throws {
        let model = DiagramViewModel(budget: DiagramBudget())
        let first = Task { await model.show(flow("A1"), dark: false) }
        let second = Task { await model.show(flow("A2"), dark: false) }
        await first.value
        await second.value
        #expect(model.state != .message(DiagramState.missingFiles))
        let none = DiagramViewModel(folder: { nil }, budget: DiagramBudget())
        await none.show(flow("A3"), dark: false)
        #expect(none.state == .message(DiagramState.missingFiles))
    }

    // MARK: Budget

    @Test func theBudgetIsAFixedNumberOfPlaces() {
        let budget = DiagramBudget(limit: 2)
        let a = budget.acquire(), b = budget.acquire()
        #expect(a != nil && b != nil && budget.inUse == 2 && budget.isFull)
        #expect(budget.acquire() == nil)
        if let a { budget.release(a) }
        #expect(budget.acquire() != nil)
        #expect(DiagramLimits.mostWebProcesses == 4)
        #expect(DiagramBudget.shared.limit == DiagramLimits.mostWebProcesses, "one budget for the whole app")
    }

    @Test func blocksPastTheLimitShowTheirSource() {
        let blocks: [Block] = (0..<(DiagramLimits.mostBlocksPerPage + 5)).map { _ in .diagram(language: "mermaid", "flowchart TB\n A --> B") }
        let draws = BlockList.draws([.rule] + blocks)
        #expect(draws.filter { $0 }.count == DiagramLimits.mostBlocksPerPage + 1)
        #expect(draws.last == false && draws.first == true)
    }

    // MARK: Click statements and navigation

    @Test func aClickStatementAfterASemicolonIsCut() {
        let text = "flowchart TB\n  A-->B; click A href \"index.html\"\n  C-->D;click C \"https://example.com\";E-->F\n  G[\"HTTPS 'x'#59; v2 #35;1\"]"
        let content = DiagramContent(.mermaid(text))
        #expect(content.mermaidText == "flowchart TB\n  A-->B\n  C-->D;E-->F\n  G[\"HTTPS 'x'#59; v2 #35;1\"]")
        #expect(content.nodes.isEmpty)
    }

    @Test func aPageNeverNavigatesToItselfOrAway() async throws {
        let page = try #require(await DiagramPage.open())
        let content = DiagramContent(.mermaid("flowchart TB\n  A-->B; click A href \"index.html\"\n  click B href \"index.html\""), allowsLinks: false)
        #expect(await page.show(content, dark: false) == .drawn)
        _ = await page.evaluate("document.querySelectorAll('g.node').forEach(n => n.dispatchEvent(new MouseEvent('click', {bubbles: true}))); return 1;")
        try await Task.sleep(for: .milliseconds(300))
        #expect(await page.evaluate("return typeof S42Diagram") as? String == "object")
        // The same file again is a navigation too: cancelled.
        _ = await page.evaluate("window.location.href = location.href.split('#')[0] + '?again'; return 1;")
        await until("the cancelled navigation") { page.cancelledNavigations > 0 }
        _ = await page.evaluate("location.reload(); return 1;")
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.cancelledNavigations >= 1)
        #expect(await page.show(content, dark: true) == .drawn, "the page is still there")
    }

    // MARK: Limits and Mermaid errors

    @Test func oneLimitForBothSides() async throws {
        let text = "flowchart TB\n" + String(repeating: "  A --> B\n", count: 6_000)
        #expect(text.utf8.count > DiagramLimits.mostMermaidBytes && text.utf8.count < 100_000)
        #expect(DiagramContent(.mermaid(text)).tooLarge)
        // Past the app's limit Mermaid draws an error picture. That is never "drawn".
        let page = try #require(await DiagramPage.open())
        #expect(await page.show(DiagramContent(.mermaid(text)), dark: false) == .failed)
        let payload = DiagramBridge.payload(for: DiagramContent(.mermaid("flowchart TB\n A --> B")), dark: false)
        #expect(payload.maxText == DiagramLimits.mostMermaidBytes)
    }

    @Test func aHostileDirectiveDoesNotChangeTheNextRender() async throws {
        let page = try #require(await DiagramPage.open())
        let hostile = "%%{init: {\"htmlLabels\": true, \"flowchart\": {\"htmlLabels\": true}, \"securityLevel\": \"loose\"}}%%\nflowchart TB\n  A[\"<b>x</b>\"] --> B"
        _ = await page.show(DiagramContent(.mermaid(hostile), allowsLinks: false), dark: false)
        _ = await page.show(flow("PLAIN"), dark: false)
        let config = await page.evaluate("return S42Diagram.config()") as? [String: Any]
        #expect(config?["htmlLabels"] as? Bool == false)
        #expect(config?["flowchartHtmlLabels"] as? Bool == false)
        #expect(config?["securityLevel"] as? String == "strict")
        #expect(await drawnText(page).contains("PLAIN"))
    }

    // MARK: Rule lists

    @Test func theRuleListKeepsItsNameAcrossLaunches() async throws {
        let folder = try #require(DiagramAssets.folder)
        let json = try DiagramBridge.ruleListJSON(allowing: folder)
        let name = DiagramPage.ruleListIdentifier(forRules: json)
        #expect(name == DiagramPage.ruleListIdentifier(forRules: json))
        #expect(name.hasPrefix("org.systems42.diagram-rules."))
        // Other rules, another folder or a rule added, give another name: an old stored list is never reused for them.
        let other = try DiagramBridge.ruleListJSON(allowing: folder.appending(path: "x"))
        #expect(DiagramPage.ruleListIdentifier(forRules: other) != name)
        #expect(DiagramPage.ruleListIdentifier(forRules: json + " ") != name)
        // The list is stored under that name and found there.
        #expect(await DiagramPage.compiledRules(allowing: folder) != nil)
        let store = try #require(WKContentRuleListStore.default())
        let stored = try? await store.contentRuleList(forIdentifier: name)
        #expect(stored != nil)
        // A name nobody compiled has no list: the lookup fails.
        let missing = try? await store.contentRuleList(forIdentifier: DiagramPage.ruleListIdentifier(forRules: other))
        #expect(missing == nil)
    }

    // MARK: A retired page ends its process

    @Test func aTimedOutDrawEndsItsProcess() async throws {
        let budget = DiagramBudget(limit: 4)
        var pids: [Int32] = []
        var views: [WeakView] = []
        for _ in 0..<3 {
            var page = await DiagramPage.open(timeout: .milliseconds(1))
            let seat = try #require(budget.acquire())
            page?.onRetire = { budget.retire(seat, view: $0) }
            if let pid = page.flatMap({ processID(of: $0.webView) }) { pids.append(pid) }
            if let web = page?.webView { views.append(WeakView(web)) }
            #expect(await page?.show(slowToDraw, dark: false) == .timedOut)
            page = nil
        }
        guard pids.count == 3 else { Issue.record("no process ids on this macOS"); return }
        // The retired pages count against the budget until their process answers, then they are released.
        await until("the budget to let go") { budget.inUse == 0 }
        await until("the web views to be released") { views.allSatisfy { $0.view == nil } }
        await until("the processes to end") { pids.allSatisfy(isGone) }
        #expect(pids.allSatisfy(isGone))
    }

    /// A web view whose script computes for `milliseconds` (or for ever), its process id, and the call that was made.
    @MainActor private func busyView(milliseconds: Int?) async -> (view: WKWebView, pid: Int32)? {
        let view = WKWebView(frame: .zero)
        view.loadHTMLString("<p>busy</p>", baseURL: nil)
        let probe = Loaded()
        view.navigationDelegate = probe
        await until("the busy view to load") { probe.done }
        guard let pid = processID(of: view) else { return nil }
        let spin = milliseconds.map { "const t = Date.now(); while (Date.now() - t < \($0)) {}" } ?? "for (;;) {}"
        view.callAsyncJavaScript(spin, arguments: [:], in: nil, in: .page) { _ in }
        return (view, pid)
    }

    @Test func stuckDrawsFillTheAppBudgetAndNothingFreesThemUntilTheProcessIsGone() async throws {
        let budget = DiagramBudget(limit: DiagramLimits.mostWebProcesses)
        var stuck: [(view: WKWebView, pid: Int32)] = []
        for _ in 0..<DiagramLimits.mostWebProcesses {
            guard let busy = await busyView(milliseconds: nil) else {
                Issue.record("no process ids on this macOS")
                for item in stuck { Darwin.kill(item.pid, SIGKILL) }
                return
            }
            stuck.append(busy)
            budget.retire(try #require(budget.acquire()), view: busy.view)
        }
        #expect(budget.inUse == DiagramLimits.mostWebProcesses && budget.isFull)
        // A request in another window draws from the same budget: it is told diagrams are busy, and opens no web view.
        var opened = 0
        let other = DiagramViewModel(folder: { opened += 1; return DiagramAssets.folder }, budget: budget)
        await other.show(flow("WAITING"), dark: false)
        #expect(other.state == .message(DiagramState.busy))
        #expect(opened == 0 && other.webView == nil)
        // However long it waits, nothing frees a place.
        try await Task.sleep(for: .seconds(3))
        #expect(budget.inUse == DiagramLimits.mostWebProcesses)
        await other.show(flow("WAITING"), dark: false)
        #expect(other.state == .message(DiagramState.busy))
        // A process that is gone frees its place. Then the waiting diagram is drawn.
        for item in stuck { Darwin.kill(item.pid, SIGKILL) }
        await until("the places to free") { budget.inUse == 0 }
        await other.show(flow("WAITING"), dark: false)
        #expect(other.state == .drawn)
        other.close()
        #expect(budget.inUse == 0)
    }

    @Test func aDrawThatAnswersLateFreesItsPlace() async throws {
        let budget = DiagramBudget(limit: 1)
        guard let busy = await busyView(milliseconds: 2_000) else { Issue.record("no process ids on this macOS"); return }
        budget.retire(try #require(budget.acquire()), view: busy.view)
        #expect(budget.isFull && budget.acquire() == nil)
        await until("the late answer") { !budget.isFull }
        #expect(budget.acquire() != nil)
    }

    @Test func theWatchDoesNotKeepTheBudgetAlive() async throws {
        weak var weakBudget: DiagramBudget?
        do {
            let budget = DiagramBudget(limit: 1)
            weakBudget = budget
            guard let busy = await busyView(milliseconds: 1_500) else { Issue.record("no process ids on this macOS"); return }
            budget.retire(try #require(budget.acquire()), view: busy.view)
        }
        await until("the budget to be released") { weakBudget == nil }
        #expect(weakBudget == nil)
    }

    @Test func threeKindsOfRunawayTextAreRefusedAndOpenNoWebView() async throws {
        let words = "flowchart TB\n  A[\"" + Array(repeating: "word", count: 9_500).joined(separator: " ") + "\"]"
        let blocks = "block-beta\n" + (0..<400).map { "block:b\($0)\n" }.joined() + "x\n" + String(repeating: "end\n", count: 400)
        let oneLine = "flowchart TB\n" + (0..<1_200).map { "subgraph s\($0)" }.joined(separator: ";") + ";A;" + Array(repeating: "end", count: 1_200).joined(separator: ";")
        let states = "stateDiagram-v2\n" + (0..<400).map { "state s\($0) {\n" }.joined() + "a --> b\n" + String(repeating: "}\n", count: 400)
        let quoted = "flowchart TB\n  A[\"" + Array(repeating: "word", count: 9_500).joined(separator: "\n") + "\"]"
        for (name, text) in [("long label", words), ("nested blocks", blocks), ("one line", oneLine), ("nested states", states), ("label over lines", quoted)] {
            #expect(text.utf8.count <= DiagramLimits.mostMermaidBytes + 5_000, Comment(rawValue: name))
            let content = DiagramContent(.mermaid(text))
            #expect(content.tooLarge, Comment(rawValue: name))
            var opened = 0
            let model = DiagramViewModel(folder: { opened += 1; return DiagramAssets.folder }, budget: DiagramBudget())
            await model.show(content, dark: false)
            #expect(model.state == .message(DiagramState.tooLarge), Comment(rawValue: name))
            #expect(opened == 0 && model.webView == nil, Comment(rawValue: name))
        }
    }

    @Test func diagramsOfTheKitAreNeverRefused() throws {
        var count = 0
        for fixture in Fixture.names {
            for name in Golden.diagrams(fixture) where name.hasSuffix(".mmd") {
                let text = try Golden.text(fixture, "diagrams/" + name)
                #expect(!DiagramContent(.mermaid(text)).tooLarge, Comment(rawValue: "\(fixture)/\(name)"))
                count += 1
            }
        }
        #expect(count > 10)
        #expect(!DiagramContent(.mermaid("flowchart TB\n  A{\"x\"} --> B{y}\n  subgraph s\n  C[\"a; b\"]\n  end")).tooLarge)
    }

    @Test func aClickWithATabIsCut() {
        let content = DiagramContent(.mermaid("flowchart TB\n  A-->B\n  click\tB href \"index.html\"\n  C-->D; click\tC href \"index.html\"\n  CLICK\u{00A0}D \"x\""))
        #expect(!content.mermaidText.lowercased().contains("click"))
        #expect(content.mermaidText == "flowchart TB\n  A-->B\n  C-->D")
    }

    // MARK: Layers

    @Test func theTermPageHasTheLayerToggles() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("basic")))
        let terms = s.store.pages(in: "domain-terms")
        var found = false
        for term in terms {
            let model = PageDiagramModel(session: s, ref: term.ref)
            await model.load()
            guard let layer = model.layers.first, case .graph(let first, _)? = model.source else { continue }
            #expect(first.nodes.allSatisfy { $0.data["core"]?.bool == true }, "terms only at first")
            model.toggle(layer.id)
            guard case .graph(let more, _)? = model.source else { Issue.record("no graph"); return }
            #expect(more.nodes.count > first.nodes.count)
            #expect(more.edges.count - first.edges.count == layer.count)
            model.toggle(layer.id)
            #expect(model.source == .graph(first, layout: DiagramLayout.termNetwork))
            found = true
            break
        }
        #expect(found, "a term of `basic` links a page of another type")
    }

    @Test func layerColoursComeFromTheTypesAreaUnlessTheStyleSheetHasOne() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("arc42")))
        let layer = TermNetworkModel.Layer(id: "decision-record", prefix: "DR", label: "Decision", count: 1)
        let area = try #require(LayerColour.area(ofType: "decision-record", in: s.metamodel))
        #expect(LayerColour.pair(of: layer, in: s.metamodel) == [LayerColour.hex(of: area, dark: false), LayerColour.hex(of: area, dark: true)])
        let known = TermNetworkModel.Layer(id: "stakeholder", prefix: "STK", label: "Stakeholder", count: 1)
        #expect(LayerColour.pair(of: known, in: s.metamodel) == ["#8a5c10", "#e6b667"])
    }
}
