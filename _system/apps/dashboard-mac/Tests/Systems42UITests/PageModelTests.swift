import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor
private func session(_ fixture: String, root: URL? = nil) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(root ?? Fixture.url(fixture)))
}

@MainActor
private func model(_ s: WikiSession, _ folder: String, _ stem: String, plain: Bool = false) throws -> PageModel {
    try #require(PageModel(session: s, ref: PageRef(folder: folder, stem: stem), reading: preference(plain: plain)))
}

@MainActor
private func preference(plain: Bool) -> ReadingPreference {
    let defaults = UserDefaults(suiteName: "s42-test-\(UUID().uuidString)")!
    let reading = ReadingPreference(defaults: defaults)
    reading.plain = plain
    return reading
}

/// A temp copy of `basic` with one page replaced.
@MainActor
private func sessionWithPage(_ folder: String, _ stem: String, text: String) async throws -> WikiSession {
    let url = try Fixture.tempCopy("basic")
    try text.write(to: url.appending(path: "wiki/\(folder)/\(stem).md"), atomically: true, encoding: .utf8)
    return try await session("basic", root: url)
}

private func ids(_ groups: [(relation: String, label: String, pages: [Page])]) -> [String] {
    Array(Set(groups.flatMap { $0.pages.map(\.id) })).sorted()
}

@MainActor @Suite struct PageModelTests {
    @Test func headShowsStatusAndEnums() async throws {
        let m = try model(try await session("basic"), "functional-requirements", "FR-004-confirm-loan")
        let status = try #require(m.head.first { $0.value == "accepted" })
        let priority = try #require(m.head.first { $0.value == "Should" })
        #expect(priority.label == "Priority")
        #expect(priority.doc == "MoSCoW")
        #expect(status.label == "Status")
        // Scalar fields are no badges.
        #expect(!m.head.contains { $0.value == "story" })
    }

    @Test func followsAreAnchors() async throws {
        let m = try model(try await session("basic"), "decisions", "DR-001-carts-expire-after-a-day")
        await m.load()
        // The anchor is the file `madr.md`, so its name is lowercase.
        #expect(m.follows.map(\.name) == ["madr"])
    }

    @Test func aFollowsLabelWithoutAnchorStaysText() async throws {
        let s = try await sessionWithPage("functional-requirements", "FR-004-confirm-loan", text: "---\nid: FR-004\ntitle: T\nstatus: draft\n---\n\n> follows [[Nothing Known]]\n\nBody.\n")
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        await m.load()
        #expect(m.follows.isEmpty)
        #expect(m.followItems.map(\.label) == ["Nothing Known"])
    }

    @Test(arguments: ["basic", "arc42-views"])
    func relationsMatchGolden(fixture: String) async throws {
        let s = try await session(fixture)
        let golden = try #require(Golden.json(fixture, "pages.json") as? [String: [String: Any]])
        var checked = 0
        for folder in s.store.folders() {
            for page in s.store.pages(in: folder) {
                let entry = try #require(golden[page.id], "\(fixture) \(page.id)")
                let m = try #require(PageModel(session: s, ref: page.ref, reading: preference(plain: false)))
                #expect(ids(m.outgoing) == entry["links_to"] as? [String], "\(fixture) \(page.id) links_to")
                #expect(ids(m.incoming) == entry["linked_from"] as? [String], "\(fixture) \(page.id) linked_from")
                checked += 1
            }
        }
        #expect(checked == golden.count)
    }

    @Test func relationLabelsComeFromTheMetamodel() async throws {
        let s = try await session("basic")
        // Outgoing: the field name made readable.
        let child = try model(s, "functional-requirements", "FR-004-confirm-loan")
        #expect(child.outgoing.first { $0.relation == "parent" }?.label == "Parent")
        // Incoming: the inverse that rel-parent.md declares.
        var labels: [String] = []
        for folder in s.store.folders() {
            for page in s.store.pages(in: folder) {
                labels += try model(s, folder, page.ref.stem).incoming.filter { $0.relation == "parent" }.map(\.label)
            }
        }
        #expect(!labels.isEmpty)
        #expect(Set(labels) == ["Children"])
    }

    @Test func openIssuesOnThePage() async throws {
        let s = try await session("search")
        let m = try model(s, "stakeholders", "STK-022-reviewer")
        #expect(m.openIssues.map(\.id) == ["ISS-001"])

        let hostile = try await session("hostile")
        let fine = try model(hostile, "domain-terms", "DT-906-fine")
        #expect(fine.openIssues.map(\.id) == ["ISS-900"])
    }

    @Test func pathNamesAreaSectionPage() async throws {
        let m = try model(try await session("basic"), "functional-requirements", "FR-002-checkout")
        #expect(m.path.count == 3)
        #expect(m.path.last == "Checkout")
    }

    @Test func plainReadingHasNoLinks() async throws {
        let s = try await session("basic")
        let linked = try model(s, "functional-requirements", "FR-004-confirm-loan")
        await linked.load()
        #expect(allLinks(linked.rendered.blocks).count > 0)
        let plain = try model(s, "functional-requirements", "FR-004-confirm-loan", plain: true)
        await plain.load()
        #expect(allLinks(plain.rendered.blocks).isEmpty)
    }

    @Test func togglingTheReadingViewChangesWhatIsShown() async throws {
        let reading = preference(plain: false)
        let m = try #require(PageModel(session: try await session("basic"), ref: PageRef(folder: "functional-requirements", stem: "FR-004-confirm-loan"), reading: reading))
        await m.load()
        #expect(!allLinks(m.rendered.blocks).isEmpty)
        reading.plain = true
        #expect(allLinks(m.rendered.blocks).isEmpty)
    }

    @Test func theTitleIsNotDrawnTwice() async throws {
        let m = try model(try await session("basic"), "functional-requirements", "FR-004-confirm-loan")
        await m.load()
        #expect(m.rendered.blocks.count == m.blocks.count + 1)
        #expect(!m.blocks.contains { if case .heading(1, _) = $0 { true } else { false } })
    }

    @Test func missingLinkIsMarked() async throws {
        let s = try await sessionWithPage("functional-requirements", "FR-004-confirm-loan", text: "---\nid: FR-004\ntitle: T\nstatus: draft\n---\n\nSee [[NOPE-999]].\n")
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        await m.load()
        let targets = allLinks(m.rendered.blocks).compactMap { inline -> LinkTarget? in
            if case .link(_, let target, _) = inline { target } else { nil }
        }
        #expect(targets == [.missing])
    }

    @Test func problemsAreShown() async throws {
        let s = try await session("hostile")
        let m = try model(s, "domain-terms", "DT-900-unclosed-frontmatter")
        await m.load()
        #expect(!m.problems.isEmpty)
        let sound = try model(try await session("basic"), "functional-requirements", "FR-004-confirm-loan")
        await sound.load()
        #expect(sound.problems.isEmpty)
    }

    @Test func hostileTextIsInert() async throws {
        let s = try await session("hostile")
        let m = try model(s, "domain-terms", "DT-911-markup-title")
        await m.load()
        #expect(m.page.title == "<script>alert(1)</script>")
        let content = InlineContent(.text(m.page.title))
        #expect(String(content.text.characters) == "<script>alert(1)</script>")
        #expect(content.actions.isEmpty)
        // The link label holds markup: it arrives as text and the link goes to a page.
        let labels = m.rendered.blocks.flatMap { block -> [String] in
            guard case .paragraph(let inlines) = block else { return [] }
            return inlines.compactMap { if case .link(let label, _, _) = $0 { InlineContent(label).text.characters.map(String.init).joined() } else { nil } }
        }
        #expect(labels == ["<b>label</b>"])
        for block in m.rendered.blocks {
            if case .paragraph(let inlines) = block {
                for action in InlineContent(inlines).actions { #expect(action.isPage) }
            }
        }
    }

    @Test func javascriptLinksAreNeverActions() {
        let bad = URL(string: "javascript:alert(1)")!
        let content = InlineContent(.url([.text("click")], bad))
        #expect(content.actions.isEmpty)
        #expect(String(content.text.characters) == "click")
        let good = InlineContent(.url([.text("go")], URL(string: "https://example.org")!))
        #expect(good.actions == [.web(URL(string: "https://example.org")!)])
        let mail = InlineContent(.url([.text("m")], URL(string: "mailto:a@b.c")!))
        #expect(mail.actions.count == 1)
    }

    @Test func linkActionsSurviveTheirURL() {
        let page = LinkAction.page(PageRef(folder: "domain terms", stem: "DT-001 é&?"))
        #expect(LinkAction(url: page.url) == page)
        let anchor = LinkAction.anchor("MADR")
        #expect(LinkAction(url: anchor.url) == anchor)
        let metamodel = LinkAction.metamodel("rel-parent")
        #expect(LinkAction(url: metamodel.url) == metamodel)
        #expect(LinkAction(url: URL(string: "https://example.org")!) == .web(URL(string: "https://example.org")!))
        #expect(LinkAction(url: URL(string: "javascript:alert(1)")!) == nil)
    }

    @Test func linkTargetsGetTheirAction() async throws {
        let s = try await session("basic")
        let page = PageRef(folder: "domain-terms", stem: "DT-002-loan")
        let inlines: [Inline] = [
            .link([.text("a")], .page(page), raw: "DT-002"),
            .link([.text("b")], .anchor("MADR"), raw: "MADR"),
            .link([.text("c")], .missing, raw: "x"),
            .link([.text("d")], .metamodel("parent"), raw: "rel-parent"),
            .link([.text("e")], .source("SRC-001"), raw: "SRC-001"),
        ]
        let content = InlineContent(inlines)
        #expect(content.actions == [.page(page), .anchor("MADR"), .metamodel("parent")])
        #expect(String(content.text.characters) == "abcde")
        _ = s
    }

    @Test func aPageLinkHasADefinitionFromItsFirstParagraph() async throws {
        let s = try await session("basic")
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        let text = try #require(m.definition(for: .page(PageRef(folder: "domain-terms", stem: "DT-002-loan"))))
        #expect(text.hasPrefix("Definition. The period during which a member holds a book"))
        #expect(!text.contains("**"))
        #expect(text.count <= 301)
        #expect(m.definition(for: .missing) == nil)
    }

    @Test func aLongDefinitionIsCut() async throws {
        let long = String(repeating: "word ", count: 120)
        let s = try await sessionWithPage("domain-terms", "DT-002-loan", text: "---\nid: DT-002\ntitle: Loan\nstatus: draft\n---\n\n# Loan\n\n\(long)\n")
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        let text = try #require(m.definition(for: .page(PageRef(folder: "domain-terms", stem: "DT-002-loan"))))
        #expect(text.count <= 301)
        #expect(text.hasSuffix("…"))
    }

    @Test func anAnchorDefinitionComesFromTheAnchor() async throws {
        let s = try await session("basic")
        let m = try model(s, "decisions", "DR-001-carts-expire-after-a-day")
        let anchor = try #require(s.metamodel.anchor("MADR"))
        #expect(m.definition(for: .anchor("MADR")) == anchor.definition)
    }

    @Test func sourcesAreTheSourceLinksOfTheFrontmatter() async throws {
        let url = try Fixture.tempCopy("basic")
        try "---\nid: FR-004\ntitle: T\nstatus: draft\nsources: [\"[[SRC-001-interview]]\"]\n---\n\nBody.\n"
            .write(to: url.appending(path: "wiki/functional-requirements/FR-004-confirm-loan.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: url.appending(path: "raw/sources"), withIntermediateDirectories: true)
        try "---\nid: SRC-001\ntype: source\ntitle: Interview\n---\n".write(to: url.appending(path: "raw/sources/SRC-001-interview.md"), atomically: true, encoding: .utf8)
        let s = try await session("basic", root: url)
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        #expect(m.sources == ["SRC-001-interview"])
        #expect(try model(try await session("basic"), "functional-requirements", "FR-002-checkout").sources.isEmpty)
    }

    @Test func aRenderedPageIsKeptPerPageAndRevision() async throws {
        let s = try await session("basic")
        let first = try model(s, "functional-requirements", "FR-004-confirm-loan")
        #expect(first.rendered.blocks.isEmpty)
        await first.load()
        #expect(!first.rendered.blocks.isEmpty)
        // A second model for the page has the blocks before it renders anything.
        let again = try model(s, "functional-requirements", "FR-004-confirm-loan")
        #expect(again.rendered == first.rendered)
        s.replace(with: LoadedWiki(root: s.root))
        let reloaded = try model(s, "functional-requirements", "FR-004-confirm-loan")
        #expect(reloaded.rendered.blocks.isEmpty)
    }

    @Test func aResultThatArrivesAfterANewRevisionIsDropped() async throws {
        let s = try await session("basic")
        let gate = Gate()
        let m = try #require(PageModel(session: s, ref: fr4, reading: preference(plain: false), render: gate.render))
        let loading = Task { await m.load() }
        await gate.untilRenderIsWaiting()
        // The wiki is replaced while the render "runs".
        s.replace(with: LoadedWiki(root: s.root))
        await gate.finishRender()
        await loading.value
        #expect(m.rendered.blocks.isEmpty)
        #expect(m.isStale)
        #expect(s.renderedPage(of: fr4) == nil)
    }

    @Test func keepingAnOldRevisionDoesNothing() async throws {
        let s = try await session("basic")
        let old = s.revision
        s.replace(with: LoadedWiki(root: s.root))
        let page = RenderedPage(follows: [], blocks: [.rule])
        s.keep(RenderedBody(normal: page, plain: page), of: fr4, revision: old)
        #expect(s.renderedPage(of: fr4) == nil)
        s.keep(RenderedBody(normal: page, plain: page), of: fr4, revision: s.revision)
        #expect(s.renderedPage(of: fr4)?.normal == page)
    }

    @Test func aPageIsRenderedOnceWhileARenderRuns() async throws {
        let s = try await session("basic")
        let gate = Gate()
        let first = try #require(PageModel(session: s, ref: fr4, reading: preference(plain: false), render: gate.render))
        let second = try #require(PageModel(session: s, ref: fr4, reading: preference(plain: false), render: gate.render))
        let a = Task { await first.load() }
        await gate.untilRenderIsWaiting()
        let b = Task { await second.load() }
        for _ in 0..<20 { await Task.yield() }
        await gate.finishRender()
        await a.value
        await b.value
        #expect(await gate.renders == 1)
        #expect(!first.rendered.blocks.isEmpty)
        #expect(!second.rendered.blocks.isEmpty)
    }

    @Test func aCancelledLoadKeepsNothing() async throws {
        let s = try await session("basic")
        let gate = Gate()
        let m = try #require(PageModel(session: s, ref: fr4, reading: preference(plain: false), render: gate.render))
        let loading = Task { await m.load() }
        await gate.untilRenderIsWaiting()
        loading.cancel()
        await gate.finishRender()
        await loading.value
        #expect(m.rendered.blocks.isEmpty)
        #expect(s.renderedPage(of: fr4) == nil)
    }

    @Test func aRemovedPageGivesNoModel() async throws {
        let s = try await session("basic")
        #expect(PageModel(session: s, ref: PageRef(folder: "functional-requirements", stem: "FR-999-gone"), reading: preference(plain: false)) == nil)
    }

    @Test func readingPreferenceIsKeptInTheDefaults() {
        let name = "s42-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let first = ReadingPreference(defaults: defaults)
        #expect(!first.plain)
        first.plain = true
        #expect(ReadingPreference(defaults: UserDefaults(suiteName: name)!).plain)
    }

    @Test(arguments: Fixture.names + ["hostile", "tailored"])
    func everyPageOpensAndEveryLinkLeadsSomewhere(fixture: String) async throws {
        let s = try await session(fixture)
        for folder in s.store.folders() {
            for page in s.store.pages(in: folder) {
                let m = try #require(PageModel(session: s, ref: page.ref, reading: preference(plain: false)))
                await m.load()
                for case .link(_, let target, _) in allLinks(m.rendered.blocks) {
                    switch target {
                    case .page(let ref): #expect(s.store.page(ref) != nil, "\(fixture) \(page.id)")
                    case .missing, .anchor, .source, .metamodel: break
                    }
                }
                for group in m.outgoing + m.incoming { #expect(!group.label.isEmpty) }
            }
        }
    }

    @Test func theDefinitionOfAnEntryIsTheFirstTextParagraphAsPlainText() async throws {
        let url = try Fixture.tempCopy("basic")
        let loan = "---\nid: DT-002\ntitle: Loan\nstatus: draft\n---\n\n# Loan\n\n1. first\n2. second\n\n- item\n\n*It* is `code` and [[DT-001-book|a book]] and [x](https://example.org).\n"
        try loan.write(to: url.appending(path: "wiki/domain-terms/DT-002-loan.md"), atomically: true, encoding: .utf8)
        let s = try await session("basic", root: url)
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        let page = try #require(s.store.page(PageRef(folder: "domain-terms", stem: "DT-002-loan")))
        #expect(m.definition(of: page) == "It is code and a book and x.")
    }

    @Test func aDefinitionFromRenderedBlocksMatchesTheCheapOne() async throws {
        let s = try await session("basic")
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        let loan = try #require(s.store.page(PageRef(folder: "domain-terms", stem: "DT-002-loan")))
        let cheap = m.definition(of: loan)
        let other = try model(s, "domain-terms", "DT-002-loan")
        await other.load()
        let fresh = try model(s, "functional-requirements", "FR-004-confirm-loan")
        #expect(fresh.definition(of: loan) == cheap)
    }

    @Test func aPageWithoutTextHasNoDefinition() async throws {
        let url = try Fixture.tempCopy("basic")
        try "---\nid: DT-002\ntitle: Loan\nstatus: draft\n---\n\n# Loan\n\n- only a list\n".write(to: url.appending(path: "wiki/domain-terms/DT-002-loan.md"), atomically: true, encoding: .utf8)
        let s = try await session("basic", root: url)
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        let page = try #require(s.store.page(PageRef(folder: "domain-terms", stem: "DT-002-loan")))
        #expect(m.definition(of: page) == nil)
    }

    @Test func everyRelationEntryWithTextHasADefinitionAndNoneWithoutText() async throws {
        let s = try await session("basic")
        let m = try model(s, "functional-requirements", "FR-004-confirm-loan")
        let entries = (m.outgoing + m.incoming).flatMap(\.pages)
        #expect(!entries.isEmpty)
        for page in entries {
            let text = m.definition(of: page)
            #expect(text == nil || (!text!.isEmpty && text!.count <= 301), "\(page.id)")
        }
        #expect(entries.contains { m.definition(of: $0) != nil })
    }

    @Test(arguments: [
        ("systems42://page?folder=domain-terms&stem=DT-001-book", false),
        ("file:///etc/hosts", false),
        ("HTTP://EXAMPLE.ORG", true),
        ("ftp://example.org/x", false),
        ("x-apple.systempreferences:", false),
    ])
    func aURLInlineOnlyActsForWebSchemes(address: String, allowed: Bool) throws {
        let url = try #require(URL(string: address))
        let content = InlineContent(.url([.text("t")], url))
        #expect(content.actions == (allowed ? [.web(url)] : []))
        #expect(content.text.runs.contains { $0.link != nil } == allowed)
    }
}

func allLinks(_ blocks: [Block]) -> [Inline] {
    func flat(_ inlines: [Inline]) -> [Inline] {
        inlines.flatMap { inline -> [Inline] in
            switch inline {
            case .link(let label, _, _): [inline] + flat(label)
            case .emphasis(let i), .strong(let i): flat(i)
            case .url(let label, _): flat(label)
            case .text, .code: []
            }
        }
    }
    return blocks.flatMap { block -> [Inline] in
        switch block {
        case .heading(_, let i), .paragraph(let i): flat(i)
        case .list(_, let items): allLinks(items.flatMap { $0 })
        case .table(let header, let rows): (header + rows.flatMap { $0 }).flatMap(flat)
        case .callout(_, let title, let inner): flat(title) + allLinks(inner)
        case .quote(let inner): allLinks(inner)
        case .code, .rule, .diagram: []
        }
    }
}

let fr4 = PageRef(folder: "functional-requirements", stem: "FR-004-confirm-loan")

/// A render the test holds back until it says go, with no sleeping.
actor Gate {
    private(set) var renders = 0
    private var waiting: CheckedContinuation<Void, Never>?
    private var released = false

    nonisolated var render: PageRender {
        { body, store in
            await self.hold()
            return await PageModel.renderBody(body, store)
        }
    }

    private func hold() async {
        renders += 1
        if released { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func untilRenderIsWaiting() async {
        while waiting == nil { await Task.yield() }
    }

    func finishRender() {
        released = true
        waiting?.resume()
        waiting = nil
    }
}
