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

@Suite(.serialized) struct MarkdownBlocksTests {
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
        let result = try blocks(String(repeating: "> ", count: 2000) + "deep text\n")
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

    /// The vectors that overflowed the parser's stack, by nesting level. Above 5,000 levels the
    /// indent stays flat, so the text stays small. The nesting bound counts markers, not indent.
    private static let deepVectors: [(name: String, make: @Sendable (Int) -> String)] = [
        ("quotes", { String(repeating: "> ", count: $0) + "x\n" }),
        ("lists by indent in a quote", { n in (0..<n).map { "> " + String(repeating: " ", count: n > 5000 ? 0 : $0 * 2) + "- x\($0)" }.joined(separator: "\n") }),
        ("nested images", { String(repeating: "![", count: $0) + "x" + String(repeating: "](u)", count: $0) }),
        ("strikethrough", { String(repeating: "~~a ", count: $0) + "x" + String(repeating: " b~~", count: $0) }),
        ("emphasis in an html tag between backticks", { "<b title=\"`" + String(repeating: "*a _b ", count: $0 / 2) + "x" + String(repeating: "_ *", count: $0 / 2) + "`\">" }),
        ("nested links", { String(repeating: "[a ", count: $0) + "x" + String(repeating: "](b)", count: $0) }),
        ("ordered lists by indent", { n in (0..<n).map { String(repeating: " ", count: n > 5000 ? 0 : $0 * 3) + "1. x\($0)" }.joined(separator: "\n") }),
        ("after a fence the parser closes differently", { "- ```a`b\n" + String(repeating: "> ", count: $0) + "x\n```\n~~~ x\n" + String(repeating: "*a ", count: $0) }),
    ]

    @Test(arguments: deepVectors.indices)
    func deepVectorsAt2000LevelsRenderWithoutCrash(_ index: Int) throws {
        let body = Self.deepVectors[index].make(2000)
        let page = try render(body)
        #expect(page.problems.isEmpty, "\(Self.deepVectors[index].name)")
        #expect(depth(page.blocks) <= 20)
        #expect(!page.blocks.isEmpty)
    }

    @Test(arguments: deepVectors.indices)
    func deepVectorsAt20000LevelsFallBackToPlainText(_ index: Int) throws {
        let body = Self.deepVectors[index].make(20_000)
        let page = try render(body)
        #expect(page.blocks == [.code(language: nil, body)], "\(Self.deepVectors[index].name)")
        #expect(page.problems == ["This page is nested too deeply to format. It is shown as plain text."])
    }

    @Test func plainReadingKeepsTheProblemAndRenderInlineStaysLiteral() throws {
        let body = String(repeating: "> ", count: 20_000) + "x"
        let page = try render(body)
        #expect(plainReading(page).problems == page.problems)
        let store = try openFixture("basic")
        #expect(renderInline(body, resolve: lookup(store), title: titleLookup(store)) == [.text(body)])
    }

    @Test func nestingBoundCountsEveryNestingCharacter() {
        #expect(nestingBound("plain text, with a - dash. And 1) numbers") == 0)
        #expect(nestingBound("- a\n  - b\n    + c") == 3)
        #expect(nestingBound("1. a\n   2) b") == 2)
        #expect(nestingBound("> > x") == 2)
        #expect(nestingBound("*a* _b_ ~~c~~ [d](e) ![f](g)") == 2 + 2 + 4 + 1 + 1)
        #expect(nestingBound("- * 1. x") == 3)
    }

    @Test func manyThreadsGetTheirOwnResult() throws {
        let store = try openFixture("basic")
        let one = renderPage("See [[FR-003]].", resolve: lookup(store), title: titleLookup(store))
        let results = LockedList<RenderedPage>()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            results.append(renderPage("See [[FR-003]].", resolve: lookup(store), title: titleLookup(store)))
        }
        #expect(results.values.count == 32 && results.values.allSatisfy { $0 == one })
    }

    @Test func aResolverThatRendersAgainDoesNotDeadlock() throws {
        let page = renderPage("[[x]]", resolve: { link in
            _ = renderInline("**\(link.name)**", resolve: { _ in .missing }, title: { _ in nil })
            return .missing
        }, title: { _ in nil })
        #expect(page.blocks == [.paragraph([.link([.text("x")], .missing, raw: "x")])])
    }

    // MARK: ordinary text stays as it is

    @Test func aLongListOfBoldItemsKeepsItsStrongText() throws {
        let body = (0..<200).map { "- **item \($0)**" }.joined(separator: "\n")
        guard case .list(false, let items)? = try blocks(body).first else { Issue.record("no list"); return }
        #expect(items.count == 200)
        #expect(items[199] == [.paragraph([.strong([.text("item 199")])])])
        #expect(items.allSatisfy { if case .paragraph(let p)? = $0.first, case .strong = p[0] { true } else { false } })
    }

    @Test func aLongTableKeepsItsBoldCells() throws {
        let body = "| A | B |\n|---|---|\n" + (0..<200).map { "| **bold \($0)** | x_y |" }.joined(separator: "\n")
        guard case .table(_, let rows)? = try blocks(body).first else { Issue.record("no table"); return }
        #expect(rows.count == 200)
        #expect(rows[0] == [[.strong([.text("bold 0")])], [.text("x_y")]])
        #expect(rows[199][0] == [.strong([.text("bold 199")])])
    }

    @Test func aLongStarLineIsARule() throws {
        #expect(try blocks(String(repeating: "*", count: 200)) == [.rule])
    }

    @Test func anAutolinkAfterManyEmphasisPairsKeepsItsUrl() throws {
        let body = String(repeating: "*a* ", count: 200) + "<https://a.org/a_b>"
        let result = try blocks(body)
        #expect(urls(result) == [.url([.text("https://a.org/a_b")], URL(string: "https://a.org/a_b")!)])
    }

    @Test func aFencedBlockInANestedListItemIsByteIdentical() throws {
        let lines = (0..<300).map { "__dunder\($0)__ = '\\\\ \\t' * 2  # *x* _y_" }
        let body = "- item\n  - nested\n    ```python\n" + lines.map { "    " + $0 }.joined(separator: "\n") + "\n    ```\n"
        func code(in blocks: [Block]) -> [Block] {
            blocks.flatMap { block -> [Block] in
                switch block {
                case .code: [block]
                case .list(_, let items): code(in: items.flatMap { $0 })
                default: []
                }
            }
        }
        #expect(code(in: try blocks(body)) == [.code(language: "python", lines.joined(separator: "\n"))])
    }

    @Test func aCodeBlockIndentedSixtySpacesKeepsItsText() throws {
        let body = "Text.\n\n" + String(repeating: " ", count: 60) + "x = 1  # *a* _b_ > c\n"
        #expect(try blocks(body) == [
            .paragraph([.text("Text.")]),
            .code(language: nil, String(repeating: " ", count: 56) + "x = 1  # *a* _b_ > c"),
        ])
    }

    // MARK: pipes in wikilinks inside tables

    @Test func aliasedWikilinkInATableCellStaysOneCell() throws {
        let body = "| A | B |\n|---|---|\n| [[FR-002-checkout|Checkout]] | 2 |\n"
        guard case .table(let header, let rows)? = try blocks(body).first else { Issue.record("no table"); return }
        #expect(header.count == 2)
        #expect(rows.count == 1 && rows[0].count == 2)
        guard case .link(let label, .page, let raw)? = rows[0][0].first else { Issue.record("no link"); return }
        #expect(text(label) == "Checkout" && raw == "FR-002-checkout")
        #expect(rows[0][1] == [.text("2")])
    }

    @Test func twoAliasedWikilinksInARowAndInTheHeader() throws {
        let body = "| [[FR-002-checkout|Out]] | B |\n|---|---|\n| [[FR-003|One]] [[FR-002-checkout#Goal|Two]] | 2 |\n"
        guard case .table(let header, let rows)? = try blocks(body).first else { Issue.record("no table"); return }
        #expect(text(header[0]) == "Out")
        #expect(rows[0].count == 2)
        #expect(text(rows[0][0]) == "One Two")
        #expect(links([.table(header: header, rows: rows)]).count == 3)
    }

    @Test func alreadyEscapedPipesAreLeftAlone() throws {
        let body = "| A | B |\n|---|---|\n| [[FR-002-checkout\\|Checkout]] | 2 |\n"
        guard case .table(_, let rows)? = try blocks(body).first else { Issue.record("no table"); return }
        #expect(rows[0].count == 2 && text(rows[0][0]) == "Checkout")
    }

    @Test func tableTextInAFenceStaysByteIdentical() throws {
        let code = "| A | B |\n|---|---|\n| [[FR-002-checkout|Checkout]] | 2 |"
        #expect(try blocks("```\n\(code)\n```\n") == [.code(language: nil, code)])
        #expect(try blocks("Intro\nuse `[[a|b]]` here\n") == [.paragraph([.text("Intro use "), .code("[[a|b]]"), .text(" here")])])
    }

    @Test func wikilinkReadsAnEscapedPipe() {
        let link = Wikilink.all(in: "[[FR-002\\|Checkout]] [[FR-002#Goal\\|Checkout]]")
        #expect(link == [Wikilink(target: "FR-002", label: "Checkout", heading: nil),
                         Wikilink(target: "FR-002", label: "Checkout", heading: "Goal")])
    }

    // MARK: follows details

    @Test func followsLabelsAsTheGoCodeDoes() throws {
        #expect(try render("> follows (the Geoffrey Moore format)\n").follows == ["(the Geoffrey Moore format)"])
        #expect(try render("> follows The   Geoffrey Moore format\n").follows == ["Geoffrey Moore format"])
        #expect(try render("> follows theory of change\n").follows == ["theory of change"])
        #expect(try render("> follows [[MADR]] (the format, section 5)\n").follows == ["MADR"])
    }

    @Test func aFollowsCommentInTheMiddleOfALineLeavesOneSpace() throws {
        let page = try render("Before <!-- follows [[Q42]] --> after\n")
        #expect(page.follows == ["Q42"])
        #expect(page.blocks == [.paragraph([.text("Before after")])])
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

/// A list that several threads may add to.
private final class LockedList<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []
    func append(_ item: Element) { lock.lock(); items.append(item); lock.unlock() }
    var values: [Element] { lock.lock(); defer { lock.unlock() }; return items }
}
