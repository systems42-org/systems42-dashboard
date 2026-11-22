import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

/// Page text must never change the shape of a Mermaid text (a title, an id or a file name is page text),
/// and a long text must never take long.

/// The shapes of the lines the builders produce. A line that fits none is a statement the builder did not mean to write.
private enum MermaidLine: Sendable {
    case header, node(id: String), edge, classDef, click, subgraph, end, direction, style, other

    private static let id = "[A-Za-z0-9]+(?:_[0-9A-Za-z]+)*"
    private static let label = "\"[^\"]*\""
    private static let cls = "(?::::[a-z]+)?"
    private static let patterns: [(String, MermaidLine)] = [
        ("^(?:graph TD|flowchart (?:LR|TB))$", .header),
        ("^  classDef [a-z]+ [a-z#0-9:,;. -]+$", .classDef),
        ("^  click (\(id)) \"[A-Za-z0-9._/#:?=&%-]+\"$", .click),
        ("^ *subgraph (\(id))\\[\(label)\\]$", .subgraph),
        ("^ *end$", .end),
        ("^    direction [A-Z]{2}$", .direction),
        ("^  style (\(id)) [a-z#0-9:,; -]+$", .style),
        ("^ *(\(id))(?:\\[\\[\(label)\\]\\]|\\(\\[\(label)\\]\\)|\\[\(label)\\])\(cls)$", .node(id: "")),
        ("^ *(\(id)) (?:-->|-\\.->|<-->)(?:\\|\(label)\\|)? (\(id))(?:\\[\\[\(label)\\]\\]|\\[\(label)\\])?\(cls)$", .edge),
        ("^ *(\(id)) (?:-- \(label) -->|-\\. \(label) \\.->) (\(id))$", .edge),
    ]

    static func classify(_ line: String) -> MermaidLine? {
        for (pattern, result) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            if case .node = result, let range = Range(match.range(at: 1), in: line) { return .node(id: String(line[range])) }
            return result
        }
        return nil
    }

    /// The ids of the nodes a line defines, alone or at the end of an edge.
    static func definedNodes(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?:^| )(\(id))(?:\\[\\[|\\(\\[|\\[)\"") else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
            Range(match.range(at: 1), in: line).map { String(line[$0]) }
        }
    }

    /// The text of a label has none of the characters that end it or start a statement. `<br/>`
    /// and entity codes such as `#59;` are written by the builders.
    static func labelsAreSafe(_ line: String) -> Bool {
        let parts = line.components(separatedBy: "\"")
        for (index, part) in parts.enumerated() where index % 2 == 1 && !line.contains("  click ") {
            let plain = part.replacingOccurrences(of: "<br/>", with: "")
                .replacingOccurrences(of: "#[0-9]+;", with: "", options: .regularExpression)
            if plain.contains(where: { "`;%{}<>|[]\n".contains($0) }) { return false }
        }
        return true
    }
}

/// Every diagram of a wiki that holds pages with hostile ids, titles and file names.
private func hostileWiki() throws -> TempWiki {
    let wiki = try TempWiki()
    let evil = "'F\"]; click Z href \"javascript:alert(1)\"; Z[\"'"
    try wiki.page("goals", "GOAL-001-vision", "Vision", "accepted", [("stereotype", "vision")])
    try wiki.page("goals", "GOAL-002-evil", "Goal `x` %% {y}", "accepted", [("stereotype", "objective")], yamlID: evil)
    func fr(_ stem: String, _ id: String, _ title: String, level: String, parent: String = "[]", goal: String = "[]") throws {
        try wiki.page("functional-requirements", stem, title, "accepted",
                      [("notation", "agile"), ("level", level), ("parent", parent), ("goal", goal)], yamlID: id)
    }
    try fr("FR-1-evil", evil, "Evil", level: "epic", goal: "[\"[[GOAL-002-evil]]\"]")
    try fr("FR-2-one", "FR1", "One", level: "epic", goal: "[\"[[GOAL-002-evil]]\"]")
    try fr("FR-3-dash", "FR-1", "Dash", level: "epic", goal: "[\"[[GOAL-002-evil]]\"]")
    try fr("FR-4-end", "end", "End", level: "epic", goal: "[\"[[GOAL-002-evil]]\"]")
    try fr("FR-5-newline", "\"a\nb\"", "New\nline", level: "epic")
    try fr("FR-6-tick", "'`x`'", "Back`tick", level: "epic")
    try fr("FR-7-comment", "'%%'", "%% comment", level: "epic")
    try fr("FR-8-feature", "style", "Feature", level: "feature", parent: "[\"[[FR-4-end]]\"]")
    try fr("FR-9-a\"b c", "FR-9", "Quote and space", level: "story", parent: "[\"[[FR-4-end]]\"]")
    for (stem, id) in [("BB-1-a", evil), ("BB-2-b", "BB1"), ("BB-3-c", "'class'")] {
        try wiki.page("building-blocks", stem, "Block \(id)", "accepted",
                      [("drivers", "[\"[[FR-4-end]]\"]"), ("uses", "[\"[[BB-2-b]]\"]")], yamlID: id)
    }
    try wiki.page("deployment-nodes", "DN-1-a", "Node", "accepted", [("hosts", "[\"[[BB-1-a]]\", \"[[BB-3-c]]\"]"),
        ("connects", "\n  - {to: \"[[DN-2-b]]\", protocol: \"x\\\" ; y\"}")], yamlID: "subgraph")
    try wiki.page("deployment-nodes", "DN-2-b", "Node two", "accepted", [("parent", "\"[[DN-1-a]]\"")], yamlID: "DN1")
    try wiki.page("runtime-scenarios", "RS-1-a", "Run", "accepted", [("steps", """

          - {from: "[[BB-1-a]]", to: "[[BB-2-b]]", message: "a %% b ; `c` <d>", note: "x\"y"}
        """)], yamlID: "RS-1")
    try wiki.page("external-interfaces", "EIF-1-a", "Partner `x`", "accepted",
                  [("flows", "\n  - {data: \"a;b\", direction: inbound, label: \"l\\\"m\"}")], yamlID: evil)
    try wiki.page("domain-terms", "DT-1-a", "Term [[x", "accepted", [("stereotype", "entity")], yamlID: evil)
    return wiki
}

@Suite struct MermaidSafetyTests {
    private let names = ["goals", "story-map", "context", "data-model", "deployment", "building-blocks"]

    private func diagrams(_ wiki: TempWiki, links: LinkStyle) throws -> [String: String] {
        let projections = try wiki.projections()
        let store = WikiStore(root: try Preflight.open(wiki.url))
        var found: [String: String] = [:]
        for name in names { if let text = projections.mermaid(name, links: links) { found[name] = text } }
        for folder in store.folders() {
            for page in store.pages(in: folder) {
                if let text = projections.mermaid("page-" + page.id, links: links) { found["page-" + page.ref.stem] = text }
            }
        }
        return found
    }

    @Test(arguments: [LinkStyle.dashboard, LinkStyle.page])
    func everyLineIsOneTheBuilderMeantToWrite(style: LinkStyle) throws {
        let wiki = try hostileWiki()
        defer { wiki.remove() }
        let found = try diagrams(wiki, links: style)
        #expect(found.count >= 8, "\(found.keys.sorted())")
        for (name, text) in found where !text.hasPrefix("sequenceDiagram") && !text.hasPrefix("classDiagram") {
            var nodeIDs: [String] = []
            var clicks = 0
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                guard let kind = MermaidLine.classify(line) else {
                    Issue.record("\(name): a line of no known shape: \(line)")
                    continue
                }
                #expect(MermaidLine.labelsAreSafe(line), "\(name): unsafe label: \(line)")
                nodeIDs += MermaidLine.definedNodes(line)
                if case .click = kind { clicks += 1 }
            }
            #expect(Set(nodeIDs).count == nodeIDs.count, "\(name): two nodes share an id: \(nodeIDs)")
            #expect(nodeIDs.allSatisfy { !NodeIDs.keywords.contains($0.lowercased()) }, "\(name): a keyword is a node id: \(nodeIDs)")
            if clicks > 0 {
                // one click for every node of a page. The group nodes have none. The Go dashboard
                // draws no click on the root of a breakdown and none in the white box or deployment diagram.
                let pageNodes = nodeIDs.filter { !["ENABLER", "NOGOAL"].contains($0) }
                if style == .page {
                    #expect(clicks == pageNodes.count, "\(name): \(clicks) clicks for \(pageNodes.count) page nodes")
                } else {
                    #expect(clicks == pageNodes.count - (name.hasPrefix("page-") ? 1 : 0), "\(name): \(clicks) clicks for \(pageNodes.count) nodes")
                }
            }
        }
    }

    @Test func equalLookingIdsGetDifferentNodeIdsAndKeywordsAreRenamed() throws {
        let wiki = try hostileWiki()
        defer { wiki.remove() }
        let map = try #require(try wiki.projections().mermaid("story-map", links: .dashboard))
        let defined = map.split(separator: "\n").flatMap { MermaidLine.definedNodes(String($0)) }
        // FR1 keeps its id, FR-1 gets a suffix, `end` is renamed
        #expect(defined.contains("FR1") && defined.contains("FR1_2"))
        #expect(defined.contains("end_2") && !defined.contains("end"))
        // the goals group keeps the Go ids where nothing clashes
        #expect(defined.contains("ENABLER") == false || defined.filter { $0 == "ENABLER" }.count == 1)
    }

    @Test func aStemWithAQuoteAndASpaceIsPercentEncodedInEveryLinkStyle() throws {
        let wiki = try hostileWiki()
        defer { wiki.remove() }
        let built = try wiki.projections()
        let dashboard = try #require(built.mermaid("page-end", links: .dashboard))
        #expect(dashboard.contains("\"/functional-requirements/FR-9-a%22b%20c\""))
        let app = try #require(built.mermaid("page-end", links: .page))
        #expect(app.contains("\"systems42://page?folder=functional-requirements&stem=FR-9-a%22b%20c\""))
        let goals = try #require(built.mermaid("goals", links: .dashboard))
        #expect(goals.contains("click V \"/goals#GOAL-001\""))
        #expect(goals.contains("/goals#F%22%5D%3B%20click%20Z%20href"))
    }

    @Test func theAppFormIsTheFormLinkActionReads() throws {
        let text = try #require(try projections("basic").mermaid("goals"))
        #expect(text.contains("click V \"systems42://page?folder=goals&stem=GOAL-001-"))
    }

    @Test func idsAndTitlesOfTheFixturesStayAsTheyAre() {
        for text in ["FR-001", "BB-007-noid", "Mitgliederkonsole", "Größe und Maß", "App-Server (Ubuntu 24.04)"] {
            #expect(Common.label(text) == text.replacingOccurrences(of: "(", with: "(").trimmingCharacters(in: .whitespaces))
        }
    }
}

@Suite struct LongTextTests {
    /// The measured time in debug is 0.9 to 1.7 s. The bound has a factor 5 of headroom
    /// over the slowest run measured (about 1.7 s for all projections of the wiki below).
    static let bound: Duration = .seconds(9)

    private func longWiki(_ text: String) throws -> TempWiki {
        let wiki = try TempWiki()
        let title = "\"\(text)\""
        try wiki.page("goals", "GOAL-001-vision", title, "accepted", [("stereotype", "vision")])
        try wiki.page("goals", "GOAL-002-obj", title, "accepted", [("stereotype", "objective")])
        try wiki.page("functional-requirements", "FR-1-a", title, "accepted",
                      [("notation", "agile"), ("level", "epic"), ("goal", "[\"[[GOAL-002-obj]]\"]")])
        try wiki.page("functional-requirements", "FR-2-b", title, "accepted",
                      [("notation", "agile"), ("level", "feature"), ("parent", "[\"[[FR-1-a]]\"]")])
        try wiki.page("functional-requirements", "UC-1-c", title, "accepted", [("notation", "use-case"), ("level", "sea"),
                      ("goal", "[\"[[GOAL-002-obj]]\"]")])
        try wiki.page("building-blocks", "BB-1-a", title, "accepted", [("drivers", "[\"[[FR-1-a]]\"]")])
        try wiki.page("building-blocks", "BB-2-b", title, "accepted", [("parent", "\"[[BB-1-a]]\""), ("uses", "[\"[[EIF-1-a]]\"]")])
        try wiki.page("deployment-nodes", "DN-1-a", title, "accepted", [("hosts", "[\"[[BB-1-a]]\"]"), ("technology", title)])
        try wiki.page("runtime-scenarios", "RS-1-a", title, "accepted", [("steps",
            "\n  - {from: \"[[BB-1-a]]\", to: \"\(text)\", message: \"\(text)\", note: \"\(text)\"}")])
        try wiki.page("external-interfaces", "EIF-1-a", title, "accepted", [("tier", "supply"),
            ("flows", "\n  - {data: \"\(text)\", direction: bidirectional, label: \"\(text)\"}")])
        try wiki.page("stakeholders", "STK-1-a", title, "accepted", [("provides", "[\"\(text)\"]"), ("context_role", title)])
        try wiki.page("domain-terms", "DT-1-a", title, "accepted", [("stereotype", "entity"),
            ("attributes", "\n  - {name: \"\(text)\"}"), ("relationships", "\n  - {to: \"[[DT-1-a]]\", label: \"\(text)\", multiplicity: \"\(text)\"}")])
        return wiki
    }

    @Test(arguments: [String(repeating: "(", count: 100_000), String(repeating: "[[", count: 100_000),
                      String(repeating: "[[a", count: 33_334), String(repeating: "(a", count: 50_000)])
    func aLongTitleTakesNoTimeInAnyProjection(text: String) throws {
        let wiki = try longWiki(text)
        defer { wiki.remove() }
        let clock = ContinuousClock()
        var produced = 0
        let elapsed = try clock.measure {
            let projections = try wiki.projections()
            let store = WikiStore(root: try Preflight.open(wiki.url))
            for name in ["goals", "story-map", "context", "data-model", "deployment", "building-blocks"] {
                if let diagram = projections.mermaid(name) { produced += 1; #expect(diagram.count < 20_000, "\(name)") }
            }
            for folder in store.folders() {
                for page in store.pages(in: folder) { if projections.mermaid("page-" + page.id) != nil { produced += 1 } }
            }
            _ = projections.hierarchy(); _ = projections.storyMap(); _ = projections.goalMatrix(); _ = projections.backlog()
            _ = projections.graph("term-network"); _ = projections.termNeighbourhood(of: "DT-1")
        }
        #expect(produced >= 10)
        #expect(elapsed < Self.bound, "took \(elapsed)")
        print("long text projections took", elapsed)
    }

    @Test func aLongLabelIsCutWithAnEllipsis() {
        let cut = Common.label(String(repeating: "a", count: 1000))
        #expect(cut.unicodeScalars.count == Common.longestLabel)
        #expect(cut.hasSuffix("…"))
        #expect(Common.label("short") == "short")
    }
}
