import AppKit
import CryptoKit
import Foundation
import Network
import os
import Testing
import WebKit
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

// Web views run in the test process without a display. Every wait below is bounded by `limit`.

private let limit: Duration = .seconds(30)

@MainActor private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

/// Polls until the condition holds or the limit passes. Records an issue on timeout.
@MainActor private func until(_ what: String, _ condition: () -> Bool) async {
    let started = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - started > limit { Issue.record("timed out waiting for \(what)"); return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor private func openPage() async throws -> DiagramPage {
    try #require(await DiagramPage.open())
}

/// A graph made the way the dashboard's JSON has it. The Kit builds its nodes itself.
private func graph(_ nodes: [[String: GraphValue]], edges: [[String: GraphValue]] = []) -> Graph {
    let json: [String: [[String: [String: GraphValue]]]] = ["nodes": nodes.map { ["data": $0] }, "edges": edges.map { ["data": $0] }]
    do { return try JSONDecoder().decode(Graph.self, from: JSONEncoder().encode(json)) } catch { return Graph() }
}

/// A server on the loopback interface that counts the connections it gets.
private final class Loopback: Sendable {
    private let listener: NWListener
    private let hits = OSAllocatedUnfairLock(initialState: 0)

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let hits = self.hits
        listener.newConnectionHandler = { connection in
            hits.withLock { $0 += 1 }
            connection.start(queue: .global())
            connection.cancel()
        }
        listener.start(queue: .global())
    }

    var count: Int { hits.withLock { $0 } }

    @MainActor func port() async -> UInt16? {
        let started = ContinuousClock.now
        while (listener.port?.rawValue ?? 0) == 0 {
            if ContinuousClock.now - started > limit { return nil }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return listener.port?.rawValue
    }

    func stop() { listener.cancel() }
}

/// Waits for a web view to finish loading.
@MainActor private final class Loaded: NSObject, WKNavigationDelegate {
    private(set) var done = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { done = true }
}

@MainActor @Suite struct DiagramTests {
    // MARK: Sources

    @Test func sourcesComeFromTheCore() async throws {
        var drawn = Set<String>()
        for name in Fixture.names {
            let s = try await session(name)
            await s.projections.load()
            let data = try #require(s.projections.data)
            let projections = Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false)
            for mode in GraphModes.mermaidModes {
                guard let source = data.diagrams[mode] else { continue }
                let kit = try #require(GraphModes.kitName(of: mode, metamodel: s.metamodel))
                // Unchanged: the text the Kit gives, with the app's links.
                #expect(source == .mermaid(try #require(projections.mermaid(kit))), "\(name) \(mode)")
                drawn.insert(mode)
            }
            // The term network starts from the Kit's graph with no layer.
            await s.termNetwork.load()
            #expect(s.termNetwork.graph == projections.termNetwork(layers: []), Comment(rawValue: name))
        }
        #expect(drawn.isSuperset(of: [GraphModes.deployment, GraphModes.buildingBlocks, GraphModes.entities, GraphModes.goalTree]))
    }

    @Test func graphModesAreOfferedFromTheMetamodel() async throws {
        let s = try await session("arc42-views")
        func modes(_ folder: String) throws -> [String] {
            let section = try #require(s.metamodel.sections.first { $0.folders.contains(folder) })
            return ProjectionHost.modes(for: section, metamodel: s.metamodel)
        }
        #expect(try modes("deployment-nodes").contains(GraphModes.deployment))
        #expect(try modes("building-blocks").contains(GraphModes.buildingBlocks))
        #expect(try modes("context").contains(GraphModes.context))
        // A mode with no drawing is not offered: the sequence diagram belongs to a page.
        #expect(try !modes("runtime-scenarios").contains("sequence-diagram"))
        // Every offered mode is a projection page of the wiki, and the session shows it as a projection.
        for section in s.metamodel.sections {
            for mode in ProjectionHost.modes(for: section, metamodel: s.metamodel) where mode != ListModel.listMode {
                #expect(s.metamodel.projections.contains { $0.name == mode })
            }
        }
    }

    // MARK: Network

    @Test func noNetwork() async throws {
        let folder = try #require(DiagramAssets.folder)
        let rules = try #require(await DiagramPage.compiledRules(allowing: folder))
        let server = try Loopback()
        defer { server.stop() }
        let port = try #require(await server.port())
        let html = "<script src=\"http://127.0.0.1:\(port)/x.js\" onerror=\"window.failed = true\"></script>"

        // Control: without the rule list the page does reach the server.
        let open = WKWebView(frame: .zero)
        let openLoad = Loaded()
        open.navigationDelegate = openLoad
        open.loadHTMLString(html, baseURL: nil)
        await until("the control page") { openLoad.done }
        await until("the control request") { server.count > 0 }
        #expect(server.count > 0)
        let before = server.count

        // With the rule list the same request is blocked, and the bundled files still load.
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(rules)
        let locked = WKWebView(frame: .zero, configuration: configuration)
        let lockedLoad = Loaded()
        locked.navigationDelegate = lockedLoad
        locked.loadHTMLString(html, baseURL: nil)
        await until("the locked page") { lockedLoad.done }
        let failed = try await locked.callAsyncJavaScript("return window.failed === true", contentWorld: .page) as? Bool
        #expect(failed == true)
        #expect(server.count == before)

        let page = try await openPage()
        let mermaid = await page.evaluate("return typeof mermaid === 'object' && typeof cytoscape === 'function'") as? Bool
        #expect(mermaid == true)
    }

    @Test func aFileOutsideTheFolderDoesNotLoad() async throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "s42-outside-\(UUID().uuidString).js")
        try "window.leak = true;".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        let page = try await openPage()
        let outcome = await page.evaluate("""
            return await new Promise(resolve => {
              const s = document.createElement('script');
              s.src = url;
              s.onload = () => resolve('loaded'); s.onerror = () => resolve('blocked');
              document.head.appendChild(s);
            });
            """, arguments: ["url": outside.absoluteString]) as? String
        #expect(outcome == "blocked")
        #expect(await page.evaluate("return window.leak === true") as? Bool == false)
    }

    @Test func theRuleListBlocksEverythingButItsFolder() throws {
        let folder = URL(fileURLWithPath: "/Applications/My App (1).app/Contents/Resources/diagram", isDirectory: true)
        let json = try DiagramBridge.ruleListJSON(allowing: folder)
        let rules = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(rules.count == 2)
        let first = try #require(rules[0]["trigger"] as? [String: String])
        #expect(first["url-filter"] == ".*" && (rules[0]["action"] as? [String: String])?["type"] == "block")
        let second = try #require(rules[1]["trigger"] as? [String: String])
        #expect((rules[1]["action"] as? [String: String])?["type"] == "ignore-previous-rules")
        // The lifted pattern is anchored, names the folder, and escapes what the pattern language reads as special.
        let pattern = try #require(second["url-filter"])
        #expect(pattern.hasPrefix("^file:///Applications/My%20App%20\\(1\\)\\.app/Contents/Resources/diagram/"))
        #expect(!pattern.contains("wiki"))
    }

    @Test func onlyTheBundledPageIsANavigationTarget() throws {
        let page = URL(fileURLWithPath: "/a/diagram/index.html")
        #expect(DiagramBridge.allowsNavigation(to: page, page: page))
        for other in ["https://example.com/", "file:///etc/hosts", "file:///a/diagram/other.html", "systems42://page?folder=a&stem=b", "javascript:alert(1)"] {
            #expect(!DiagramBridge.allowsNavigation(to: URL(string: other), page: page), "\(other)")
        }
        #expect(!DiagramBridge.allowsNavigation(to: nil, page: page))
    }

    @Test func aScriptCannotNavigateAwayOrOpenAWindow() async throws {
        let page = try await openPage()
        let opened = await page.evaluate("return window.open('https://example.com/') === null") as? Bool
        #expect(opened == true)
        _ = await page.evaluate("window.location.href = 'https://example.com/'; return 1;")
        await until("the cancelled navigation") { page.cancelledNavigations > 0 }
        #expect(page.cancelledNavigations > 0)
        #expect(await page.evaluate("return location.pathname.endsWith('index.html')") as? Bool == true)
    }

    @Test func theWebViewKeepsNothingAndReadsOnlyItsFolder() async throws {
        let page = try await openPage()
        #expect(!page.webView.configuration.websiteDataStore.isPersistent)
        #expect(!page.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
    }

    // MARK: Hostile text

    private static let hostileLabel = "<img src=x onerror=\"window.webkit.messageHandlers.select.postMessage('pwned')\">"

    @Test func hostileLabelIsInert() async throws {
        let page = try await openPage()
        var selected: [String] = []
        page.onSelect = { selected.append($0) }
        let hostile = graph([
            ["id": .string("A"), "label": .string(Self.hostileLabel), "type": .string("DT"), "core": .bool(true)],
            ["id": .string("B"), "label": .string("</script><script>window.webkit.messageHandlers.select.postMessage('pwned')</script>"),
             "type": .string("DT"), "core": .bool(true)],
        ], edges: [["id": .string("e0"), "source": .string("A"), "target": .string("B")]])
        let outcome = await page.show(DiagramContent(.graph(hostile, layout: DiagramLayout.termNetwork)), dark: false)
        #expect(outcome == .drawn)
        #expect(await page.evaluate("return S42Diagram.count()") as? Int == 2)
        _ = await page.evaluate("S42Diagram.tap('A'); return 1;")
        try? await Task.sleep(for: .milliseconds(300))
        #expect(selected.isEmpty)
        #expect(page.acceptedMessages == 0 && page.droppedMessages == 0, "the page posted a message of its own")
    }

    @Test func hostileMermaidTextIsInert() async throws {
        let page = try await openPage()
        var selected: [String] = []
        page.onSelect = { selected.append($0) }
        let texts = [
            "flowchart TB\n  A[\"\"]; click A call alert(1); A[\"\"] --> B[\"<img src=x onerror=window.webkit.messageHandlers.select.postMessage('pwned')>\"]",
            "flowchart TB\n  A[\"x\"] --> B[\"y\"]\n  click A href \"javascript:window.webkit.messageHandlers.select.postMessage('pwned')\"\n  click B call window.webkit.messageHandlers.select.postMessage('pwned')()",
        ]
        for text in texts {
            // A block of a page body: the author's text. No click line survives, and no node opens a page.
            let content = DiagramContent(.mermaid(text), allowsLinks: false)
            #expect(!content.mermaidText.contains("javascript:"))
            #expect(content.nodes.isEmpty)
            _ = await page.show(content, dark: false)
            _ = await page.evaluate("document.querySelectorAll('g.node').forEach(n => n.dispatchEvent(new MouseEvent('click', {bubbles: true}))); return 1;")
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(selected.isEmpty)
        #expect(page.acceptedMessages == 0 && page.droppedMessages == 0)
    }

    @Test func aPageTitleCannotBecomeAClickLine() async throws {
        // The Kit writes the title of a page into Mermaid text. A title that tries to add a statement stays a label.
        let copy = try Fixture.tempCopy("arc42-views")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let folder = copy.appending(path: "wiki/building-blocks")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }.sorted()
        let first = folder.appending(path: try #require(files.first))
        var text = try String(contentsOf: first, encoding: .utf8)
        let range = try #require(text.range(of: "\ntitle: "))
        let end = try #require(text[range.upperBound...].firstIndex(of: "\n"))
        text.replaceSubrange(range.upperBound..<end, with: "'\"]; click A call alert(1); A[\"'")
        try text.write(to: first, atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        await s.projections.load()
        let source = try #require(s.projections.data?.diagrams[GraphModes.buildingBlocks])
        guard case .mermaid(let mermaid) = source else { Issue.record("not mermaid"); return }
        let statements = mermaid.split(separator: "\n").map { $0.drop { $0 == " " } }
        #expect(!statements.contains { $0.hasPrefix("click A call") })
        #expect(!mermaid.contains("alert(1);"))
        let page = try await openPage()
        var selected: [String] = []
        page.onSelect = { selected.append($0) }
        #expect(await page.show(DiagramContent(source), dark: false) == .drawn)
        #expect(selected.isEmpty && page.acceptedMessages == 0)
    }

    // MARK: Clicks and validation

    @Test func clickReportsTheNodeId() async throws {
        let page = try await openPage()
        var selected: [String] = []
        page.onSelect = { selected.append($0) }
        let mermaid = "flowchart TB\n  A[\"One\"] --> B[\"Two\"]\n  click A \"systems42://page?folder=goals&stem=GOAL-001-x\"\n  click B \"systems42://page?folder=goals&stem=GOAL-002-y\""
        let content = DiagramContent(.mermaid(mermaid))
        #expect(content.nodes.map(\.id) == ["A", "B"])
        #expect(content.node(id: "B")?.ref == PageRef(folder: "goals", stem: "GOAL-002-y"))
        #expect(await page.show(content, dark: false) == .drawn)
        _ = await page.evaluate("document.querySelectorAll('g.node')[1].dispatchEvent(new MouseEvent('click', {bubbles: true})); return 1;")
        await until("the click") { !selected.isEmpty }
        #expect(selected == ["B"])

        selected = []
        let terms = graph([
            ["id": .string("DT-001-a"), "label": .string("A"), "type": .string("DT"), "core": .bool(true), "url": .string("/page/domain-terms/DT-001-a")],
            ["id": .string("DT-002-b"), "label": .string("B"), "type": .string("DT"), "core": .bool(true), "url": .string("/page/domain-terms/DT-002-b")],
        ], edges: [["id": .string("e0"), "source": .string("DT-001-a"), "target": .string("DT-002-b")]])
        #expect(await page.show(DiagramContent(.graph(terms, layout: DiagramLayout.termNetwork)), dark: true) == .drawn)
        _ = await page.evaluate("return S42Diagram.tap('DT-002-b');")
        await until("the graph click") { !selected.isEmpty }
        #expect(selected == ["DT-002-b"])
    }

    @Test func aMessageThatIsNoKnownNodeIsDropped() async throws {
        let page = try await openPage()
        var selected: [String] = []
        page.onSelect = { selected.append($0) }
        let content = DiagramContent(.mermaid("flowchart TB\n  A[\"One\"]\n  click A \"systems42://page?folder=goals&stem=GOAL-001-x\""))
        #expect(await page.show(content, dark: false) == .drawn)
        for body in ["'other'", "42", "null", "{id: 'A'}", "['A']", "'A '", "''", "true"] {
            _ = await page.evaluate("window.webkit.messageHandlers.select.postMessage(\(body)); return 1;")
        }
        await until("the dropped messages") { page.droppedMessages >= 7 }
        // postMessage turns a number into a number and 'A ' stays a different string: none is the id.
        #expect(selected.isEmpty)
        // A message after the diagram was cleared is dropped too.
        page.clear()
        _ = await page.evaluate("window.webkit.messageHandlers.select.postMessage('A'); return 1;")
        await until("the late message") { page.droppedMessages >= 9 }
        #expect(selected.isEmpty)
    }

    @Test func bridgeMessagesAreValidated() {
        let known: Set<String> = ["A", "B_2", "DT-001-a"]
        #expect(DiagramBridge.validated("A", known: known) == "A")
        #expect(DiagramBridge.validated("DT-001-a", known: known) == "DT-001-a")
        #expect(DiagramBridge.validated("a", known: known) == nil)
        #expect(DiagramBridge.validated("", known: known) == nil)
        #expect(DiagramBridge.validated(" A", known: known) == nil)
        #expect(DiagramBridge.validated(1, known: known) == nil)
        #expect(DiagramBridge.validated(["A"], known: known) == nil)
        #expect(DiagramBridge.validated(["id": "A"], known: known) == nil)
        #expect(DiagramBridge.validated(NSNull(), known: known) == nil)
        #expect(DiagramBridge.validated("A", known: []) == nil)
    }

    @Test func clickLinesNeverReachThePage() {
        let text = "flowchart TB\n  A[\"x\"]\n  click A \"systems42://page?folder=f&stem=s\"\n    CLICK B \"javascript:alert(1)\"\n  click C call f()\n  click D href \"https://example.com\""
        let content = DiagramContent(.mermaid(text))
        #expect(content.mermaidText == "flowchart TB\n  A[\"x\"]")
        // Only the page reference of the app becomes a node.
        #expect(content.nodes == [.init(id: "A", ref: PageRef(folder: "f", stem: "s"))])
        let payload = DiagramBridge.payload(for: content, dark: false)
        #expect(!payload.text.lowercased().contains("click"))
        #expect(payload.links == ["A"])
    }

    @Test func dataGoesToThePageAsJSON() throws {
        let nasty = "a \"quote\" and \\ backslash\n</script><script>x()</script> \u{2028} é"
        let content = DiagramContent(.mermaid("flowchart TB\n  A[\"\(nasty)\"]"))
        let object = try #require(DiagramBridge.argument(for: DiagramBridge.payload(for: content, dark: true)) as? [String: Any])
        #expect(object["theme"] as? String == "dark")
        #expect(object["text"] as? String == content.mermaidText)
        #expect(object["kind"] as? String == "mermaid")
    }

    // MARK: Text list

    @Test func everyNodeIsAlsoText() async throws {
        let s = try await session("domain-model")
        let projections = Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false)
        let network = try #require(projections.graph("term-network"))
        let content = DiagramContent(.graph(network, layout: DiagramLayout.termNetwork))
        let withPage = network.nodes.filter { ($0.data["url"]?.string ?? "").hasPrefix("/page/") }
        #expect(!withPage.isEmpty)
        #expect(content.nodes.count == withPage.count)
        // Each of them is a page of the wiki.
        for node in content.nodes { #expect(node.ref.flatMap { s.store.page($0) } != nil, "\(node.id)") }
        // A diagram of Mermaid text: one node per click line of the Kit.
        let views = try await session("arc42-views")
        let deployment = try #require(Projections(store: views.store, metamodel: views.metamodel, agreedOnly: false).mermaid("deployment"))
        let clicks = deployment.split(separator: "\n").filter { $0.drop { $0 == " " }.hasPrefix("click ") }.count
        #expect(DiagramContent(.mermaid(deployment)).nodes.count == clicks)
        #expect(clicks > 0)
        // The metamodel graph has no pages: its nodes are the types, and a section group is no node.
        let metamodel = try #require(projections.graph("metamodel-graph"))
        let types = DiagramContent(.graph(metamodel, layout: DiagramLayout.metamodel)).nodes
        #expect(types.count == s.metamodel.types.count)
        #expect(types.allSatisfy { $0.ref == nil })
    }

    @Test func aDiagramOfTheAuthorOpensNoPage() {
        let text = "flowchart TB\n  A[\"x\"]\n  click A \"systems42://page?folder=f&stem=s\""
        #expect(DiagramContent(.mermaid(text), allowsLinks: false).nodes.isEmpty)
    }

    // MARK: Term network

    @Test func termNetworkStartsWithTermsOnly() async throws {
        let s = try await session("domain-model")
        let model = s.termNetwork
        await model.load()
        #expect(model.isCurrent)
        #expect(!model.graph.nodes.isEmpty)
        #expect(model.graph.nodes.allSatisfy { $0.data["core"]?.bool == true })
        let prefixes = Set(model.graph.nodes.compactMap { $0.data["type"]?.string })
        #expect(prefixes == [s.metamodel.type(named: "domain-term")?.prefix ?? ""])
    }

    @Test func layerToggleAddsAndRemoves() async throws {
        let s = try await session("basic")
        let model = s.termNetwork
        await model.load()
        let first = model.graph
        let layer = try #require(model.layers.first { $0.id == "stakeholder" })
        #expect(layer.count > 0)
        model.toggle("stakeholder")
        #expect(model.isOn("stakeholder") && !model.isCurrent)
        await model.load()
        #expect(model.isCurrent)
        #expect(model.graph.nodes.count > first.nodes.count)
        let added = Set(model.graph.nodes.map(\.id)).subtracting(first.nodes.map(\.id))
        let prefix = try #require(s.metamodel.type(named: "stakeholder")?.prefix)
        #expect(added.allSatisfy { $0.hasPrefix(prefix + "-") })
        // The toggle's count is the number of edges it adds.
        #expect(model.graph.edges.count - first.edges.count == layer.count)
        model.toggle("stakeholder")
        await model.load()
        #expect(model.graph == first)
        // A name that is no layer does nothing.
        model.toggle("domain-term")
        #expect(model.enabled.isEmpty)
    }

    @Test func aStaleTermNetworkIsDropped() async throws {
        let s = try await session("basic")
        let model = s.termNetwork
        await model.load()
        model.toggle("stakeholder")
        // The agreed-only switch changes the key while the layer is on: the graph that arrives is for the key at the end.
        let loading = Task { await model.load() }
        s.agreedOnly = true
        await loading.value
        await model.load()
        #expect(model.isCurrent)
        #expect(model.loadedKey?.agreedOnly == true)
    }

    // MARK: Limits and missing files

    @Test func aTooLargeDiagramIsNotDrawn() async throws {
        let big = "flowchart TB\n" + String(repeating: "  A --> B\n", count: DiagramLimits.mostMermaidBytes / 10 + 10)
        #expect(DiagramContent(.mermaid(big)).tooLarge)
        let many = graph((0...DiagramLimits.mostGraphNodes).map { ["id": .string("n\($0)")] })
        #expect(DiagramContent(.graph(many, layout: DiagramLayout.termNetwork)).tooLarge)
        let edges = graph([["id": .string("a")]], edges: (0...DiagramLimits.mostGraphEdges).map { ["id": .string("e\($0)"), "source": .string("a"), "target": .string("a")] })
        #expect(DiagramContent(.graph(edges, layout: DiagramLayout.termNetwork)).tooLarge)
        #expect(!DiagramContent(.mermaid("flowchart TB\n  A --> B")).tooLarge)

        var opened = 0
        let model = DiagramViewModel(folder: { opened += 1; return DiagramAssets.folder }, budget: DiagramBudget())
        await model.show(DiagramContent(.mermaid(big)), dark: false)
        #expect(model.state == .message(DiagramState.tooLarge))
        #expect(opened == 0, "no web view for a diagram that is not drawn")
    }

    @Test func missingFilesShowAMessageAndDoNotStopTheApp() async throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "s42-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(DiagramAssets.locate(in: [empty]) == nil)
        #expect(await DiagramPage.open(folder: nil) == nil)
        let model = DiagramViewModel(folder: { nil }, budget: DiagramBudget())
        await model.show(DiagramContent(.mermaid("flowchart TB\n  A --> B")), dark: false)
        #expect(model.state == .message(DiagramState.missingFiles))
        #expect(DiagramAssets.report(folder: nil) == "diagram assets: missing")
        let result = try #require(DiagramAssetCheck.run([DiagramAssetCheck.flag], folder: nil))
        #expect(result.status == 1)
        #expect(DiagramAssetCheck.run(["--other"], folder: nil) == nil)
    }

    @Test func theFilesAreFoundInBothBundleLayouts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "s42-layout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for inner in DiagramAssets.insideBundle {
            let place = root.appending(path: inner.isEmpty ? "flat" : "macos")
            let folder = place.appending(path: DiagramAssets.bundleName).appending(path: inner).appending(path: DiagramAssets.folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(DiagramAssets.locate(in: [place]) == nil)
            try "<html></html>".write(to: folder.appending(path: DiagramAssets.pageName), atomically: true, encoding: .utf8)
            #expect(DiagramAssets.locate(in: [place])?.standardizedFileURL == folder.standardizedFileURL)
        }
    }

    @Test func theCheckFlagFindsTheFiles() throws {
        let result = try #require(DiagramAssetCheck.run([DiagramAssetCheck.flag]))
        #expect(result.status == 0, "\(result.lines)")
        #expect(result.lines.first?.hasPrefix("diagram assets: found at ") == true)
    }

    @Test func aNewerShowSupersedesAnOlderOne() async throws {
        let page = try await openPage()
        let slow = DiagramContent(.mermaid("flowchart TB\n  A --> B"))
        let fast = DiagramContent(.mermaid("flowchart TB\n  C --> D"))
        // Two tasks on the main actor start in order: the second asks while the first waits for the page.
        let first = Task { await page.show(slow, dark: false) }
        let second = Task { await page.show(fast, dark: false) }
        #expect(await second.value == .drawn)
        #expect(await first.value == .superseded)
    }

    @Test func aBrokenMermaidTextIsAMessage() async throws {
        let page = try await openPage()
        #expect(await page.show(DiagramContent(.mermaid("flowchart TB\n  A -->")), dark: false) == .failed)
        #expect(await page.show(DiagramContent(.mermaid("not a diagram at all")), dark: false) == .failed)
    }

    // MARK: Assets

    @Test func assetsMatchTheDashboard() throws {
        // The copies are pinned by checksum in CHECKSUMS. `scripts/sync-diagram-assets.sh --check`
        // compares them with the dashboard, by hand or in CI.
        let folder = try #require(DiagramAssets.folder)
        let listed = try String(contentsOf: folder.appending(path: "CHECKSUMS"), encoding: .utf8)
            .split(separator: "\n").map { $0.components(separatedBy: "  ") }
        #expect(listed.count >= 7)
        for entry in listed {
            #expect(entry.count == 2)
            guard entry.count == 2 else { continue }
            let data = try Data(contentsOf: folder.appending(path: entry[1]))
            let sum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(sum == entry[0], "\(entry[1]) differs from its pinned checksum")
        }
        let source = try String(contentsOf: folder.appending(path: "SOURCE"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(source.count == 40)
    }

    // MARK: Page diagrams and the metamodel graph

    @Test func aTermPageShowsItsNeighbourhood() async throws {
        let s = try await session("domain-model")
        let term = try #require(s.store.pages(in: "domain-terms").first { $0.id == "DT-001" })
        let model = PageDiagramModel(session: s, ref: term.ref)
        await model.load()
        guard case .graph(let graph, let layout)? = model.source else { Issue.record("no neighbourhood"); return }
        #expect(layout == DiagramLayout.termNetwork)
        #expect(graph == Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false).termNeighbourhood(of: term.ref.stem))
        #expect(graph.nodes.contains { $0.data["focus"]?.bool == true })
    }

    @Test func aBuildingBlockPageShowsItsWhiteBox() async throws {
        let s = try await session("arc42-views")
        let block = try #require(s.store.pages(in: "building-blocks").first { $0.id == "BB-001" })
        let model = PageDiagramModel(session: s, ref: block.ref)
        await model.load()
        guard case .mermaid(let text)? = model.source else { Issue.record("no diagram"); return }
        #expect(text == Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false).mermaid("page-BB-001"))
        // A page of a type with no diagram gets none.
        let issue = try #require(s.store.pages(in: "decisions").first)
        let none = PageDiagramModel(session: s, ref: issue.ref)
        await none.load()
        #expect(none.source == nil)
    }

    @Test func theMetamodelGraphLoadsAndClickOpensTheType() async throws {
        let s = try await session("basic")
        let model = s.explainer
        await model.loadGraph()
        let graph = try #require(model.drawnGraph)
        #expect(graph == Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false).graph("metamodel-graph"))
        model.mode = .graph
        let type = try #require(s.metamodel.types.first { $0.name == "stakeholder" })
        model.show(link: MetamodelModel.Link(kind: MetamodelModel.types, name: type.name, title: type.name))
        #expect(model.mode == .entries)
        #expect(model.selectedEntry?.name == type.name)
    }

    @Test func aMetamodelGraphDrawsAndTapsOpenNoPage() async throws {
        let s = try await session("basic")
        let page = try await openPage()
        var selected: [String] = []
        page.onSelect = { selected.append($0) }
        let graph = try #require(Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false).graph("metamodel-graph"))
        let content = DiagramContent(.graph(graph, layout: DiagramLayout.metamodel))
        #expect(await page.show(content, dark: true) == .drawn)
        #expect(await page.evaluate("return S42Diagram.count()") as? Int == graph.nodes.count)
        _ = await page.evaluate("return S42Diagram.tap('stakeholder');")
        await until("the type tap") { selected == ["stakeholder"] }
        #expect(selected == ["stakeholder"])
    }
}
