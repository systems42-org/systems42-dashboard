import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

private func lookup(_ store: WikiStore) -> (Wikilink) -> LinkTarget { { store.resolve($0) } }

private func titleLookup(_ store: WikiStore) -> (LinkTarget) -> String? {
    { target in
        switch target {
        case .page(let ref): store.page(ref)?.title
        case .anchor(let name), .metamodel(let name), .source(let name): name
        case .missing: nil
        }
    }
}

private func render(_ body: String, _ fixture: String = "basic") throws -> RenderedPage {
    let store = try openFixture(fixture)
    return renderPage(body, resolve: lookup(store), title: titleLookup(store))
}

private func blocks(_ body: String) throws -> [Block] { try render(body).blocks }

/// The text of inlines with every mark and link dropped.
private func text(_ inlines: [Inline]) -> String {
    inlines.map { inline in
        switch inline {
        case .text(let s), .code(let s): s
        case .emphasis(let i), .strong(let i), .link(let i, _, _), .url(let i, _): text(i)
        }
    }.joined()
}

/// Every inline of a block tree, in order, however deep.
private func allInlines(_ blocks: [Block]) -> [Inline] {
    func flat(_ inlines: [Inline]) -> [Inline] {
        inlines.flatMap { inline -> [Inline] in
            switch inline {
            case .emphasis(let i), .strong(let i), .link(let i, _, _), .url(let i, _): [inline] + flat(i)
            default: [inline]
            }
        }
    }
    return blocks.flatMap { block -> [Inline] in
        switch block {
        case .heading(_, let i), .paragraph(let i): flat(i)
        case .list(_, let items): allInlines(items.flatMap { $0 })
        case .table(let header, let rows): (header + rows.flatMap { $0 }).flatMap(flat)
        case .callout(_, let title, let inner): flat(title) + allInlines(inner)
        case .quote(let inner): allInlines(inner)
        case .code, .rule, .diagram: []
        }
    }
}

private func links(_ blocks: [Block]) -> [Inline] {
    allInlines(blocks).filter { if case .link = $0 { true } else { false } }
}

private func urls(_ blocks: [Block]) -> [Inline] {
    allInlines(blocks).filter { if case .url = $0 { true } else { false } }
}

private func plain(_ blocks: [Block]) -> String { text(allInlines(blocks).filter { if case .text = $0 { true } else { false } }) }

@Suite struct MarkdownBlocksTests {
    // MARK: the brief

    @Test func wikilinkWithLabel() throws {
        let result = try blocks("See [[FR-002-checkout|Checkout]].")
        let expected = LinkTarget.page(ref("functional-requirements", "FR-002-checkout"))
        #expect(result == [.paragraph([
            .text("See "), .link([.text("Checkout")], expected, raw: "FR-002-checkout"), .text("."),
        ])])
    }

    @Test func wikilinkInCodeStaysText() throws {
        let body = "`[[FR-002]]`\n\n```\n[[FR-002]]\n```\n\n~~~\n[[FR-002]]\n~~~\n\n    [[FR-002]]\n"
        let result = try blocks(body)
        #expect(links(result).isEmpty)
        #expect(result.contains(.code(language: nil, "[[FR-002]]")))
        #expect(allInlines(result).contains(.code("[[FR-002]]")))
    }

    @Test func calloutWithKindAndTitle() throws {
        let result = try blocks("> [!assumption] Not checked\n> The vendor said so.\n")
        #expect(result == [.callout(kind: "assumption", title: [.text("Not checked")],
                                    [.paragraph([.text("The vendor said so.")])])])
    }

    @Test func followsBecomesALabel() throws {
        let one = try render("> follows [[MADR]]\n\nBody.\n")
        #expect(one.follows == ["MADR"])
        #expect(one.blocks == [.paragraph([.text("Body.")])])
        let two = try render("> follows [[user-story-format]], [[INVEST]]\n")
        #expect(two.follows == ["user-story-format", "INVEST"])
        #expect(two.blocks.isEmpty)
    }

    @Test func tableKeepsCells() throws {
        let body = "| A | B | C |\n|---|---|---|\n| 1 | [[FR-002-checkout\\|Checkout]] | 3 |\n| 4 | 5 | 6 |\n"
        let result = try blocks(body)
        guard case .table(let header, let rows)? = result.first else { Issue.record("no table"); return }
        #expect(header.count == 3)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count == 3 })
        #expect(links([result[0]]).count == 1)
        #expect(text(rows[0][1]) == "Checkout")
    }

    @Test func nestedListsKeepDepth() throws {
        let body = "- first\n  1. one\n  2. two\n- second\n\n  Another paragraph.\n"
        let result = try blocks(body)
        #expect(result == [.list(ordered: false, items: [
            [.paragraph([.text("first")]),
             .list(ordered: true, items: [[.paragraph([.text("one")])], [.paragraph([.text("two")])]])],
            [.paragraph([.text("second")]), .paragraph([.text("Another paragraph.")])],
        ])])
    }

    @Test func mermaidBlockIsADiagram() throws {
        #expect(try blocks("```mermaid\ngraph TD\n  A --> B\n```\n")
                == [.diagram(language: "mermaid", "graph TD\n  A --> B")])
        #expect(try blocks("```swift\nlet x = 1\n```\n") == [.code(language: "swift", "let x = 1")])
    }

    @Test func scriptTagIsText() throws {
        for html in ["<script>alert(1)</script>", "<img src=x onerror=alert(1)>"] {
            let block = try blocks(html)
            #expect(block == [.paragraph([.text(html)])], "\(html)")
            let inline = try blocks("Before \(html) after")
            #expect(urls(inline).isEmpty && links(inline).isEmpty)
            #expect(text(allInlines(inline)) == "Before \(html) after", "\(html)")
        }
    }

    @Test func javascriptLinkIsText() throws {
        for dest in ["javascript:alert(1)", "file:///etc/passwd", "JaVaScRiPt:alert(1)", "data:text/html,x",
                     "&#106;avascript:alert(1)", "relative/page.md", "#anchor", "//evil.example/x"] {
            let result = try blocks("[x](\(dest))")
            #expect(urls(result).isEmpty, "\(dest)")
            #expect(result == [.paragraph([.text("x")])], "\(dest)")
        }
        let angle = try blocks("[x](<javascript:alert(1)>)")
        #expect(urls(angle).isEmpty)
    }

    @Test func titleWithMarkdown() throws {
        let store = try openFixture("basic")
        let title = try #require(store.page(id: "DR-001")?.title)
        #expect(title == "Carts expire after **one day**")
        let inlines = renderInline(title, resolve: lookup(store), title: titleLookup(store))
        #expect(inlines == [.text("Carts expire after "), .strong([.text("one day")])])
    }

    @Test func plainReadingDropsBracketsAndIds() throws {
        let page = try render("See [[FR-002-checkout|Checkout]] and [[FR-003]].")
        #expect(links(page.blocks).count == 2)
        let reading = plainReading(page)
        #expect(links(reading.blocks).isEmpty)
        #expect(reading.blocks == [.paragraph([.text("See Checkout and Scan a Book.")])])
    }

    @Test func everyFixturePageRenders() throws {
        var stores: [WikiStore] = []
        for name in Fixture.names + ["hostile"] { stores.append(try openFixture(name)) }
        var count = 0
        let start = ContinuousClock.now
        for store in stores {
            for folder in store.folders() {
                for page in store.pages(in: folder) {
                    _ = renderPage(page.body, resolve: lookup(store), title: titleLookup(store))
                    count += 1
                }
            }
        }
        #expect(count > 50)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    // MARK: cases the brief misses

    @Test func linkLabelWithoutAliasIsTheTitle() throws {
        let result = try blocks("[[FR-003]] [[MADR]] [[nowhere/Gone]] [[raw/sources/SRC-404]]")
        let shown = links(result).map { text([$0]) }
        #expect(shown == ["Scan a Book", "MADR", "Gone", "SRC-404"])
    }

    @Test func wikilinkInsideEmphasisHeadingAndTableCell() throws {
        let result = try blocks("# About [[FR-003]]\n\n*see [[FR-002-checkout]]*\n\n| H |\n|---|\n| [[FR-003]] |\n")
        #expect(links(result).count == 3)
        guard case .heading(1, let head)? = result.first else { Issue.record("no heading"); return }
        #expect(text(head) == "About Scan a Book")
        guard case .paragraph(let para) = result[1], case .emphasis(let inner) = para[0] else {
            Issue.record("no emphasis"); return
        }
        #expect(links([.paragraph(inner)]).count == 1)
    }

    @Test func wikilinkInsideALinkLabelIsPlainText() throws {
        let result = try blocks("[see [[FR-003]]](https://example.org)")
        #expect(urls(result).count == 1)
        #expect(links(result).isEmpty)
        #expect(plain(result) == "see Scan a Book")
    }

    @Test func httpHttpsAndMailtoLinksAreUrls() throws {
        let result = try blocks("[a](http://a.example) [b](https://b.example/x?y=1) [c](mailto:me@b.example)")
        #expect(urls(result).count == 3)
    }

    @Test func autolinkIsAUrl() throws {
        let result = try blocks("Go to <https://example.org/a>.")
        #expect(result == [.paragraph([
            .text("Go to "), .url([.text("https://example.org/a")], URL(string: "https://example.org/a")!), .text("."),
        ])])
    }

    @Test func imageBecomesItsAltText() throws {
        #expect(try blocks("![a cat](https://example.org/cat.png)") == [.paragraph([.text("a cat")])])
        #expect(try blocks("![](https://example.org/cat.png)") == [.paragraph([])])
        #expect(try blocks("![x](javascript:alert(1))") == [.paragraph([.text("x")])])
    }

    @Test func calloutWithoutTitleGetsItsKindAsTitle() throws {
        let result = try blocks("> [!note]\n> The target is a proposal.\n")
        #expect(result == [.callout(kind: "note", title: [.text("Note")],
                                    [.paragraph([.text("The target is a proposal.")])])])
        #expect(try blocks("> [!WARNING]\n") == [.callout(kind: "warning", title: [.text("Warning")], [])])
    }

    @Test func calloutKeepsMoreBlocksAndMarkedTitle() throws {
        let result = try blocks("> [!note] The **big** one\n> first\n>\n> - item\n")
        #expect(result == [.callout(kind: "note", title: [.text("The "), .strong([.text("big")]), .text(" one")], [
            .paragraph([.text("first")]), .list(ordered: false, items: [[.paragraph([.text("item")])]]),
        ])])
    }

    @Test func ordinaryQuoteStaysAQuote() throws {
        #expect(try blocks("> Said it once.\n") == [.quote([.paragraph([.text("Said it once.")])])])
    }

    @Test func followsInsideACalloutKeepsTheCalloutWhole() throws {
        let page = try render("> [!note] Hinweis\n> follows [[MADR]]\n> Zweite Zeile.\n")
        #expect(page.follows == ["MADR"])
        #expect(page.blocks == [.callout(kind: "note", title: [.text("Hinweis")],
                                         [.paragraph([.text("Zweite Zeile.")])])])
    }

    @Test func followsInTheMiddleOfAPageIsRemovedThereToo() throws {
        let page = try render("Intro.\n\n> follows [[PAM]]\n\nAfter.\n\n> follows [[pam]] (again)\n")
        #expect(page.follows == ["PAM"])
        #expect(page.blocks == [.paragraph([.text("Intro.")]), .paragraph([.text("After.")])])
    }

    @Test func followsInCodeAndOrdinaryQuotesStay() throws {
        let body = "```markdown\n> follows [[MADR]]\n```\n\nIndented:\n\n    > follows [[MADR]]\n\n"
            + "> Follows from the interview that users want export.\n\n"
            + "> follows the interview of 2026-11-12, which says that users want an export.\n"
        let page = try render(body)
        #expect(page.follows.isEmpty)
        #expect(page.blocks.filter { if case .quote = $0 { true } else { false } }.count == 2)
        #expect(page.blocks.contains(.code(language: "markdown", "> follows [[MADR]]")))
    }

    @Test func followsWithoutALinkIsAPlainLabel() throws {
        let page = try render("> follows the Geoffrey Moore format\n")
        #expect(page.follows == ["Geoffrey Moore format"])
        #expect(page.blocks.isEmpty)
    }

    @Test func followsAsACommentIsRemovedAndReturned() throws {
        let page = try render("**Scenario.**  <!-- follows [[Q42]], https://quality.arc42.org -->\n\nText.\n")
        #expect(page.follows == ["Q42"])
        #expect(page.blocks == [.paragraph([.strong([.text("Scenario.")])]), .paragraph([.text("Text.")])])
        let block = try render("<!-- follows [[Q42]] -->\n\nText.\n")
        #expect(block.follows == ["Q42"])
        #expect(block.blocks == [.paragraph([.text("Text.")])])
    }

    @Test func taskListItemKeepsItsBox() throws {
        let result = try blocks("- [ ] open\n- [x] done\n")
        #expect(result == [.list(ordered: false, items: [
            [.paragraph([.text("☐ open")])], [.paragraph([.text("☑ done")])],
        ])])
    }

    @Test func hardAndSoftBreaks() throws {
        #expect(try blocks("one\ntwo") == [.paragraph([.text("one two")])])
        #expect(try blocks("one  \ntwo") == [.paragraph([.text("one\ntwo")])])
        #expect(try blocks("one\\\ntwo") == [.paragraph([.text("one\ntwo")])])
    }

    @Test func strikethroughKeepsItsText() throws {
        #expect(try blocks("~~gone~~ here") == [.paragraph([.text("gone here")])])
    }

    @Test func footnoteDoesNotCrashAndKeepsItsText() throws {
        let result = try blocks("Claim[^1].\n\n[^1]: The note.\n")
        let all = text(allInlines(result))
        #expect(all.contains("Claim"))
        #expect(all.contains("The note."))
        #expect(urls(result).isEmpty)
    }

    @Test func rulesAndHeadings() throws {
        #expect(try blocks("## Two\n\n---\n\nSetext\n===\n") == [
            .heading(level: 2, [.text("Two")]), .rule, .heading(level: 1, [.text("Setext")]),
        ])
    }

    @Test func htmlBlockWithSeveralLinesIsOneTextBlock() throws {
        let result = try blocks("<div>\n<a href=\"javascript:x\">y</a>\n</div>\n")
        #expect(result == [.paragraph([.text("<div>\n<a href=\"javascript:x\">y</a>\n</div>")])])
    }

    @Test func emptyBodyGivesNothing() throws {
        let page = try render("")
        #expect(page.blocks.isEmpty && page.follows.isEmpty)
    }

    @Test func crlfLinesAreLines() throws {
        let page = try render("> follows [[MADR]]\r\n\r\nBody\r\n")
        #expect(page.follows == ["MADR"])
        #expect(page.blocks == [.paragraph([.text("Body")])])
    }

    @Test func wikilinkWithHeadingKeepsTheTarget() throws {
        let result = try blocks("[[FR-002-checkout#Goal|the goal]]")
        guard case .paragraph(let p)? = result.first, case .link(let label, _, let raw) = p[0] else {
            Issue.record("no link"); return
        }
        #expect(text(label) == "the goal")
        #expect(raw == "FR-002-checkout")
    }

    // MARK: robustness

    @Test func deepQuotesAreCappedAndKeepTheirText() throws {
        let body = String(repeating: "> ", count: 2000) + "deep text\n"
        let result = try blocks(body)
        #expect(plain(result) == "deep text")
        #expect(depth(result) <= 20)
    }

    @Test func deepListsAreCappedAndKeepTheirText() throws {
        var body = ""
        for level in 0..<2000 { body += String(repeating: " ", count: level * 2) + "- item\(level)\n" }
        let result = try blocks(body)
        #expect(plain(result).contains("item0"))
        #expect(plain(result).contains("item1999"))
        #expect(depth(result) <= 20)
    }

    @Test func deepEmphasisAndBracketsDoNotCrash() throws {
        let nested = String(repeating: "*a _b ", count: 3000) + "x" + String(repeating: "_ *", count: 3000)
        _ = try blocks(nested)
        _ = try blocks(String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000))
        _ = try blocks(String(repeating: "[[", count: 5000))
        _ = try blocks(String(repeating: "[x](", count: 3000))
    }

    @Test func manyDelimitersStillReadAsTheirText() throws {
        let words = (0..<400).map { "snake_case_\($0)" }.joined(separator: " ")
        #expect(plain(try blocks(words)) == words)
        let code = String(repeating: "`a_b` ", count: 400)
        #expect(allInlines(try blocks(code)).filter { $0 == .code("a_b") }.count == 400)
    }

    @Test func deepMixedNestingDoesNotCrash() throws {
        let body = String(repeating: "> - ", count: 1500) + "x\n"
        #expect(plain(try blocks(body)).contains("x"))
    }

    @Test func plainReadingAlsoFlattensUrlsAndKeepsTheRest() throws {
        let page = try render("**Bold** [a](https://a.example) `code` [[FR-003]]\n\n> [!note] See [[FR-002-checkout]]\n> x\n")
        let reading = plainReading(page)
        #expect(links(reading.blocks).isEmpty && urls(reading.blocks).isEmpty)
        guard case .paragraph(let first)? = reading.blocks.first else { Issue.record("no paragraph"); return }
        #expect(first == [.strong([.text("Bold")]), .text(" a "), .code("code"), .text(" Scan a Book")])
        guard case .callout(_, let title, _)? = reading.blocks.last else { Issue.record("no callout"); return }
        #expect(text(title) == "See Checkout")
    }
}

/// How deep blocks nest.
private func depth(_ blocks: [Block]) -> Int {
    1 + (blocks.map { block -> Int in
        switch block {
        case .list(_, let items): depth(items.flatMap { $0 })
        case .quote(let inner), .callout(_, _, let inner): depth(inner)
        default: 0
        }
    }.max() ?? 0)
}
