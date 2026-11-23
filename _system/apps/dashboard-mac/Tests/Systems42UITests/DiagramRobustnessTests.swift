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
        let model = DiagramViewModel(timeout: .seconds(5))
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
        let model = DiagramViewModel(timeout: .milliseconds(1))
        await model.show(slowToDraw, dark: false)
        #expect(model.state == .message(DiagramState.tookTooLong))
        #expect(model.page == nil)
        // The next show opens a new page.
        let again = DiagramViewModel(timeout: .seconds(10))
        await again.show(flow("FAST"), dark: false)
        #expect(again.state == .drawn)
    }

    @Test func deeplyNestedSubgraphsAreRefusedBeforeTheyHangAProcess() {
        // 400 nested levels took 3 s in Mermaid, 1,200 took 13 s, 2,500 ran for minutes: a draw that cannot be stopped.
        for depth in [DiagramLimits.mostSubgraphDepth + 1, 400, 1_200, 2_500] {
            #expect(DiagramContent(.mermaid(nested(depth))).tooLarge, "\(depth)")
        }
        #expect(!DiagramContent(.mermaid(nested(DiagramLimits.mostSubgraphDepth))).tooLarge)
        // Flat subgraphs are not nesting, and `end` words in other places do not count.
        let flat = "flowchart TB\n" + String(repeating: "subgraph a\nA\nend\n", count: 100)
        #expect(!DiagramContent(.mermaid(flat)).tooLarge)
    }

    // MARK: Requests supersede each other

    @Test func theLatestOfTwoRequestsIsDrawn() async throws {
        let model = DiagramViewModel()
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
        let model = DiagramViewModel()
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
        let model = DiagramViewModel()
        let light = Task { await model.show(flow("THEME"), dark: false) }
        let dark = Task { await model.show(flow("THEME"), dark: true) }
        await light.value
        await dark.value
        #expect(model.state == .drawn)
        #expect(await model.page?.evaluate("return document.documentElement.getAttribute('data-theme')") as? String == "dark")
    }

    @Test func filesAreMissingOnlyWhenTheyAre() async throws {
        let model = DiagramViewModel()
        let first = Task { await model.show(flow("A1"), dark: false) }
        let second = Task { await model.show(flow("A2"), dark: false) }
        await first.value
        await second.value
        #expect(model.state != .message(DiagramState.missingFiles))
        let none = DiagramViewModel(folder: { nil })
        await none.show(flow("A3"), dark: false)
        #expect(none.state == .message(DiagramState.missingFiles))
    }

    // MARK: Budget

    @Test func aWindowHasAFixedNumberOfLiveViews() {
        let budget = DiagramBudget(limit: 2)
        let a = DiagramSlot(), b = DiagramSlot(), c = DiagramSlot()
        #expect(budget.acquire(a) && budget.acquire(b))
        #expect(!budget.acquire(c) && !c.isLive)
        #expect(budget.acquire(a), "asking again is no second place")
        #expect(budget.liveCount == 2)
        budget.claim(c)
        #expect(c.isLive && !a.isLive && b.isLive, "the view that had a place longest gives it up")
        budget.release(b)
        #expect(budget.liveCount == 1 && !b.isLive)
        #expect(DiagramLimits.mostLiveViews == 4)
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
            page?.onRetire = { budget.noteRetired($0) }
            if let pid = page.flatMap({ processID(of: $0.webView) }) { pids.append(pid) }
            if let web = page?.webView { views.append(WeakView(web)) }
            #expect(await page?.show(slowToDraw, dark: false) == .timedOut)
            page = nil
        }
        guard pids.count == 3 else { Issue.record("no process ids on this macOS"); return }
        // The retired pages count against the budget until their process answers, then they are released.
        await until("the budget to let go") { budget.retiredAlive == 0 }
        await until("the web views to be released") { views.allSatisfy { $0.view == nil } }
        await until("the processes to end") { pids.allSatisfy(isGone) }
        #expect(pids.allSatisfy(isGone))
    }

    @Test func aRetiredViewCountsAgainstTheBudgetUntilItAnswers() async throws {
        let budget = DiagramBudget(limit: 1)
        let web = WKWebView(frame: .zero)
        budget.noteRetired(web)
        #expect(budget.retiredAlive == 1)
        #expect(!budget.acquire(DiagramSlot()), "a retired view that is not gone holds the place")
        await until("the view to answer") { budget.retiredAlive == 0 }
        #expect(budget.acquire(DiagramSlot()))
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
