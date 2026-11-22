import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

/// Diagrams the golden data does not cover, on small wikis built like the Python tests do
/// (`test_context_projection.py`, `test_data_model_diagram.py`, `test_arc42_views.py`).
@Suite struct GoldenCoverageTests {
    /// Pins how many golden files exist, so the golden walk cannot pass by finding nothing.
    @Test func everyGoldenFileIsWalked() {
        let counts = Dictionary(uniqueKeysWithValues: Fixture.names.map { name in
            (name, [".mmd", ".json"].map { ext in Golden.diagrams(name).filter { $0.hasSuffix(ext) }.count })
        })
        #expect(counts["arc42"] == [6, 5])
        #expect(counts["arc42-views"] == [14, 1])
        #expect(counts["basic"] == [4, 9])
        #expect(counts["domain-model"] == [2, 8])
        #expect(counts["search"] == [1, 7])
    }
}

@Suite struct CommonTextTests {
    @Test func labelsFollowCleanLabel() {
        #expect(Common.cleanLabel("Fraud & Security", dropParenthetical: true) == "Fraud and Security")
        #expect(Common.cleanLabel("Orders (v2)", dropParenthetical: true) == "Orders")
        #expect(Common.cleanLabel("Orders (v2)", dropParenthetical: false) == "Orders (v2)")
        #expect(Common.cleanLabel("See [[wiki/DT-001-book|the book]] and [[DT-002-loan]]", dropParenthetical: true) == "See the book and DT-002-loan")
        #expect(Common.cleanLabel("a <b> \"c\" | [d]", dropParenthetical: true) == "a b c d")
        #expect(Common.cleanLabel("  many \t\n spaces ", dropParenthetical: true) == "many spaces")
    }

    @Test func nodeIdsAndEscapes() {
        #expect(Common.diagramNodeID("BB-007-noid") == "BB007noid")
        #expect(Common.diagramNodeID("---") == "N")
        #expect(Common.mmEscape("a #1; b\n c") == "a #35;1#59; b c")
        #expect(Common.edgeText("say \"hi\"") == "say 'hi'")
    }
}

@Suite struct AgreedOnlyRuleTests {
    @Test func aPageIsHiddenOnlyWhenItsLifecycleHasTheAgreedStatus() throws {
        let store = WikiStore(root: try Preflight.open(Fixture.url("basic")))
        let metamodel = store.metamodel
        let draft = try #require(store.page(id: "FR-006"))
        let accepted = try #require(store.page(id: "FR-001"))
        #expect(metamodel.isHiddenWhenAgreedOnly(draft))
        #expect(!metamodel.isHiddenWhenAgreedOnly(accepted))
        // an issue's lifecycle has no agreed status: nothing is hidden
        let hostile = WikiStore(root: try Preflight.open(Fixture.url("hostile")))
        let issue = try #require(hostile.pages(in: "issues").first { $0.status == "open" })
        #expect(!hostile.metamodel.isHiddenWhenAgreedOnly(issue))
        let hidden = Projections(store: store, metamodel: metamodel, agreedOnly: true).hierarchy().map(\.id)
        #expect(!hidden.contains("FR-006"))
        #expect(hidden.contains("FR-001"))
    }
}

@Suite struct ContextDiagramTests {
    private func eif(_ wiki: TempWiki, _ num: String, _ title: String, tier: String, flows: [String],
                     shortTitle: String? = nil, partner: String? = nil, status: String = "draft") throws {
        var fields = [("partner", partner ?? title), ("tier", tier)]
        if let shortTitle { fields.append(("short_title", shortTitle)) }
        fields.append(("flows", "\n" + flows.map { "  - { \($0) }" }.joined(separator: "\n")))
        try wiki.page("external-interfaces", "EIF-\(num)-\(title.lowercased())", title, status, fields)
    }

    private func contextWiki() throws -> TempWiki {
        let wiki = try TempWiki()
        try eif(wiki, "001", "Artists", tier: "supply", flows: [
            "data: artwork submissions and tour participation, direction: inbound, label: artwork",
            "data: sale notifications and commission statements, direction: outbound, label: sales",
        ], shortTitle: "Artists", partner: "Artists, individual creators who submit work")
        try eif(wiki, "002", "Buyers", tier: "demand", flows: [
            "data: purchase intent and payment, direction: inbound, label: orders",
            "data: confirmations, direction: outbound, label: orders",
        ], shortTitle: "Buyers")
        try eif(wiki, "003", "Regulator", tier: "core-operations", flows: ["data: tax filings, direction: outbound, label: filings"],
                partner: "Tax authorities, AML/KYC providers and law enforcement")
        try eif(wiki, "004", "Analytics", tier: "support", flows: [
            "data: an extremely long payload description that would wreck the layout, direction: inbound",
        ])
        try eif(wiki, "005", "Payments", tier: "core-operations", flows: [
            "data: card authorisations, direction: outbound, label: payments",
            "data: settlement reports, direction: inbound, label: settlement",
        ], shortTitle: "Payments", status: "deprecated")
        return wiki
    }

    private func edges(_ diagram: String) -> [String] {
        diagram.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { ($0.contains("-->") || $0.contains("<-->")) && !$0.contains("classDef") }
    }

    @Test func oneLinePerNeighbourWithShortDeduplicatedLabels() throws {
        let wiki = try contextWiki()
        defer { wiki.remove() }
        let diagram = try #require(wiki.projections().mermaid("context"))
        let e = edges(diagram)
        #expect(e.count == 4)
        #expect(e.filter { $0.contains("<-->") }.count == 2)
        #expect(e.contains { $0.contains("<-->|\"artwork · sales\"|") })
        #expect(e.contains { $0.contains("<-->|\"orders\"|") })
        #expect(!diagram.contains("orders · orders"))
        // supply lays out left of the centre, demand right
        #expect(e.contains { $0.hasPrefix("EIF001 <-->") })
        #expect(e.contains { $0.hasPrefix("CORE <-->") && $0.contains("EIF002") })
    }

    @Test func nodeLabelsPreferShortTitleThenTitleNeverPartner() throws {
        let wiki = try contextWiki()
        defer { wiki.remove() }
        let diagram = try #require(wiki.projections().mermaid("context"))
        #expect(diagram.contains("[\"Artists\"]"))
        #expect(diagram.contains("[\"Regulator\"]"))
        #expect(!diagram.contains("Tax authorities"))
        for band in ["Supply", "Support", "Demand", "Core operations"] { #expect(diagram.contains("[\"\(band)\"]"), "\(band)") }
        #expect(diagram.contains("CORE[\"System X\"]:::core"))
    }

    @Test func anUnlabelledFlowClipsItsDataAndADeprecatedNeighbourIsNotDrawn() throws {
        let wiki = try contextWiki()
        defer { wiki.remove() }
        let diagram = try #require(wiki.projections().mermaid("context"))
        let long = try #require(edges(diagram).first { $0.contains("EIF004") })
        #expect(long.contains("…") && long.count < 90)
        #expect(!diagram.contains("Payments"))
        #expect(!edges(diagram).contains { $0.contains("payments") || $0.contains("settlement") })
    }

    @Test func stakeholdersGroupByRoleAndNoneIsLeftOut() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("stakeholders", "STK-001-ann", "Ann", "draft", [("provides", "[orders]"), ("receives", "[invoices]"), ("context_role", "Customer")])
        try wiki.page("stakeholders", "STK-002-bob", "Bob", "draft", [("provides", "[orders, returns]"), ("context_role", "Customer")])
        try wiki.page("stakeholders", "STK-003-cy", "Cy", "draft", [("provides", "[x]"), ("context_role", "none")])
        try wiki.page("stakeholders", "STK-004-org", "Org", "draft", [("receives", "[reports]"), ("nature", "organization")])
        let diagram = try #require(wiki.projections().mermaid("context"))
        #expect(diagram.contains("Customer([\"Person · Customer\"]):::actor"))
        #expect(diagram.contains("Org[\"Org\"]:::system"))
        #expect(diagram.contains("Customer <-->|\"orders · returns · invoices\"| CORE"))
        #expect(!diagram.contains("Cy"))
        #expect(diagram.contains("CORE -->|\"reports\"| Org"))
    }

    @Test func noEdgeGivesNoDiagram() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("stakeholders", "STK-001-ann", "Ann", "draft")
        #expect(try wiki.projections().mermaid("context") == nil)
    }
}

@Suite struct DataModelDiagramTests {
    @Test func classNamesAreSafeAndUnique() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("domain-terms", "DT-001-a", "Größe (Maß)", "draft", [("stereotype", "value-object"), ("attributes", "\n  - {name: a b}\n  - {name: \"x/y\"}\n  - {name: \"\"}")])
        try wiki.page("domain-terms", "DT-002-b", "Grösse", "draft", [("stereotype", "entity")])
        try wiki.page("domain-terms", "DT-003-c", "1st Order", "draft", [("stereotype", "sum-type")])
        try wiki.page("domain-terms", "DT-004-d", "Plain term", "draft")
        try wiki.page("domain-terms", "DT-005-e", "---", "draft", [("stereotype", "entity")])
        let diagram = try #require(wiki.projections().mermaid("data-model"))
        #expect(diagram == """
            classDiagram
              class Groesse["Größe"] {
                  <<value-object>>
                  +a b
                  +x#47;y
              }
              class Groesse2["Grösse"]
              class E1stOrder["1st Order"] {
                  <<sum-type>>
              }
              class Entity["---"]
            """)
    }

    @Test func edgesKeepKindCardinalityAndDirection() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        let rel = "\n  - {to: \"[[DT-002-b]]\", kind: aggregation, multiplicity: \"0..*\", label: has}\n  - {to: \"[[DT-001-a]]\"}\n  - {to: \"[[DT-001-a]]\", kind: inheritance}\n  - {to: \"[[DT-002-b]]\", kind: generalization}\n  - {to: \"[[DT-099-x]]\"}\n  - {to: \"[[DT-002-b]]\", kind: weird, multiplicity: 1}"
        try wiki.page("domain-terms", "DT-001-a", "Alpha", "draft", [("stereotype", "entity"), ("relationships", rel)])
        try wiki.page("domain-terms", "DT-002-b", "Beta", "draft", [("stereotype", "sum-type")])
        try wiki.page("domain-terms", "DT-003-c", "Gamma", "draft", [("stereotype", "entity"), ("parent", "\"[[DT-002-b]]\"")])
        let diagram = try #require(wiki.projections().mermaid("data-model"))
        let lines = diagram.split(separator: "\n").map(String.init)
        #expect(lines.contains("  Alpha o-- \"0..*\" Beta : has"))
        #expect(lines.contains("  Alpha --> Alpha"))
        #expect(!lines.contains("  Alpha <|-- Alpha"))
        #expect(lines.contains("  Beta <|-- Alpha"))
        #expect(lines.contains("  Beta <|-- Gamma"))
        #expect(lines.contains("  Alpha --> \"1\" Beta"))
        #expect(!diagram.contains("DT099"))
    }
}

@Suite struct ArchitectureDiagramTests {
    @Test func aSequenceNamesPagesByStemLinkOrTextAndMarksTheGaps() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("stakeholders", "STK-001-user", "User", "draft")
        try wiki.page("building-blocks", "BB-001-web", "Web (ui)", "draft")
        try wiki.page("runtime-scenarios", "RS-001-login", "Login", "draft", [("steps", """

              - {from: "[[STK-001-user]]", to: BB-001-web, message: "open #1; now"}
              - not a step
              - {from: BB-001-web, to: "wiki/building-blocks/BB-001-web", message: "", note: "twice; ok"}
              - {from: BB-001-web, to: ghost, message: x}
              - {from: BB-001-web, message: y}
            """)])
        let projections = try wiki.projections()
        let expected = """
            sequenceDiagram
              actor L1 as User
              participant L2 as BB-001 · Web
              participant L3 as ghost
              participant L4 as ?
              L1->>L2: open #35;1#59; now
              L2->>L2: \u{20}
              Note over L2: twice#59; ok
              L2->>L3: x
              L2->>L4: y
            """
        #expect(projections.mermaid("page-RS-001") == expected)
        #expect(projections.mermaid("runtime/RS-001") == expected)
        #expect(projections.mermaid("runtime/BB-001") == nil)
    }

    @Test func aScenarioWithoutStepsHasNoDiagram() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("runtime-scenarios", "RS-001-login", "Login", "draft")
        #expect(try wiki.projections().mermaid("page-RS-001") == nil)
    }

    @Test func aWhiteBoxDrawsUsesEdgesOutsideBlocksAndNeighbours() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("external-interfaces", "EIF-001-pay", "Pay", "draft")
        try wiki.page("building-blocks", "BB-001-top", "Top", "draft", [("uses", "[\"[[BB-004-far]]\"]")])
        try wiki.page("building-blocks", "BB-002-a", "A", "draft", [("state", "current"), ("parent", "\"[[BB-001-top]]\""), ("uses", "[\"[[BB-003-b]]\", \"[[BB-004-far]]\", \"[[EIF-001-pay]]\", \"[[BB-009-none]]\"]")])
        try wiki.page("building-blocks", "BB-003-b", "B", "draft", [("parent", "\"[[BB-001-top]]\""), ("state", "planned")])
        try wiki.page("building-blocks", "BB-004-far", "Far", "draft", [("state", "current"), ("superseded-by", "[\"[[BB-003-b]]\"]")])
        let projections = try wiki.projections()
        #expect(projections.mermaid("page-BB-002") == nil)
        let white = try #require(projections.mermaid("page-BB-001"))
        #expect(white == """
            flowchart LR
              BB002["BB-002 · A"]:::block
              BB003["BB-003 · B · planned"]:::block
              BB004["BB-004 · Far · being replaced"]:::outside
              EIF001["Pay"]:::system
              BB002 --> BB003
              BB002 --> BB004
              BB002 --> EIF001
              style BB003 stroke-dasharray:5 4
              BB004 -. "replaced by" .-> BB003
              classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;
              classDef outside fill:#e3ecf7,stroke:#2f6fb3,stroke-dasharray:4 3,color:#15202e;
              classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;
            """)
    }
}

@Suite struct TermNetworkUnitTests {
    @Test func relatedLinksAreOnePairAndCrossEdgesNameTheirType() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("domain-terms", "DT-001-a", "A", "draft", [("related", "[\"[[DT-002-b]]\", \"[[STK-001-s]]\", \"[[DT-001-a]]\", \"[[DT-404-x]]\"]"), ("aliases", "[Alpha, Eins]"), ("agreed", "true")])
        try wiki.page("domain-terms", "DT-002-b", "B", "deprecated", [("related", "[\"[[DT-001-a]]\"]")])
        try wiki.page("stakeholders", "STK-001-s", "S", "draft")
        let graph = try #require(try wiki.projections().graph("term-network"))
        #expect(graph.edges.map(\.id) == ["e0", "e1"])
        #expect(graph.edges.map { "\($0.source)>\($0.target)" } == ["DT-001-a>DT-002-b", "DT-001-a>STK-001-s"])
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.data) })
        #expect(nodes["DT-001-a"]?["state"]?.string == "agreed")
        #expect(nodes["DT-001-a"]?["aliases"]?.string == "Alpha, Eins")
        #expect(nodes["DT-001-a"]?["degree"] == .int(1))
        #expect(nodes["DT-002-b"]?["state"]?.string == "deprecated")
        #expect(nodes["STK-001-s"]?["type"]?.string == "STK")
        #expect(nodes["STK-001-s"]?["rest"] == nil)
        #expect(graph.extra["layer_counts"] == .map(["STK": .int(1)]))
        // the ego graph of a term that is no node is empty
        #expect(try wiki.projections().termNeighbourhood(of: "STK-404").nodes.isEmpty)
    }
}

@Suite struct MetamodelGraphTests {
    @Test func blocksTypesAndRelationEdgesFollowTheMetamodel() throws {
        let graph = try #require(try projections("basic").graph("metamodel-graph"))
        let blocks = graph.nodes.filter { $0.data["is_block"]?.bool == true }.map(\.id)
        #expect(blocks.first == "block:R1")
        #expect(blocks.contains("block:A5"))
        let types = graph.nodes.filter { $0.data["is_block"] == nil }
        #expect(types.count == 17)
        #expect(types.last?.id == "source")
        // a relation from a type to itself is a loop edge with a direction of its own
        #expect(graph.edges.contains { $0.data["loop_dir"] != nil })
        #expect(graph.edges.enumerated().allSatisfy { $0.element.id == "e\($0.offset)" })
        guard case .list(let universal)? = graph.extra["universal"] else { Issue.record("no universal"); return }
        #expect(universal.count == 3)
    }

    @Test func noMetamodelGivesAnEmptyGraph() throws {
        let wiki = try TempWiki(metamodel: false)
        defer { wiki.remove() }
        let graph = try #require(try wiki.projections().graph("metamodel-graph"))
        #expect(graph.nodes.isEmpty && graph.edges.isEmpty)
    }
}

@Suite struct GraphCodingTests {
    @Test func aGraphEncodesAsCytoscapeDataAndReadsBack() throws {
        let graph = try #require(try projections("basic").graph("term-network"))
        let data = try JSONEncoder().encode(graph)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["nodes", "edges", "layer_counts"])
        let first = try #require((object["nodes"] as? [[String: Any]])?.first)
        #expect(first["data"] is [String: Any])
        #expect(try JSONDecoder().decode(Graph.self, from: data) == graph)
    }
}
