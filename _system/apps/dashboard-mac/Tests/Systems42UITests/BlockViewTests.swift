import SwiftUI
import Testing
import Systems42Kit
@testable import Systems42UI

@MainActor @Suite struct BlockViewTests {
    /// One block of every case, with links, marks and a long line in it.
    static let everyCase: [Block] = [
        .heading(level: 2, [.text("Heading"), .code("x")]),
        .paragraph([.text("Text "), .strong([.text("bold")]), .emphasis([.text("it")]), .link([.text("go")], .missing, raw: "x")]),
        .list(ordered: true, items: [[.paragraph([.text("one")])], [.paragraph([.text("two")]), .list(ordered: false, items: [[.paragraph([.text("deep")])]])]]),
        .table(header: [[.text("A")], [.text("B")]], rows: [[[.text("1")], [.text("2")]]]),
        .code(language: "swift", "let x = 1"),
        .callout(kind: "note", title: [.text("Note")], [.paragraph([.text("inside")])]),
        .quote([.paragraph([.text("quoted")])]),
        .rule,
        .diagram(language: "mermaid", "graph TD; A-->B"),
    ]

    @Test func everyBlockCaseHasAView() throws {
        for block in Self.everyCase {
            let view = BlockView(block: block).frame(width: 400)
            let renderer = ImageRenderer(content: view)
            let image = try #require(renderer.cgImage, "\(block)")
            #expect(image.width > 0 && image.height > 0)
        }
    }

    @Test func everyBlockCaseHasADescription() {
        let kinds = Self.everyCase.map { BlockView.kind(of: $0) }
        #expect(Set(kinds).count == Self.everyCase.count)
    }

    @Test func aMermaidBlockIsADiagram() {
        #expect(BlockView.kind(of: .diagram(language: "mermaid", "x")) == .diagram)
    }

    @Test func aCalloutKindIsOnlyAStyleLookup() {
        let known = CalloutStyle(kind: "note")
        let unknown = CalloutStyle(kind: "something-new")
        #expect(!known.symbol.isEmpty)
        #expect(!unknown.symbol.isEmpty)
    }
}
