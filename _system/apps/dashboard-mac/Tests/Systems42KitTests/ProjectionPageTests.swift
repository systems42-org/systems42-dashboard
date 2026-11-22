import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

/// The projection pages of the metamodel (`_system/metamodel/projections/proj-*.md`) and the code that implements them.
@Suite struct ProjectionPageTests {
    /// Types and fields the code reads that the projection page does not declare in `reads:`. The pages
    /// list types and field names, and the code needs more: values, the keys inside a step or a flow, the
    /// state of an architecture page. This list is the open debt (CON-006). When a page starts to declare
    /// one, the entry fails the test and goes.
    ///
    /// Fields: projection name, then type name, then the fields.
    static let undeclaredFields: [String: [String: Set<String>]] = [
        // the lifecycle mark of a block or node in a diagram (`state`, `superseded-by`), and the label suffix
        "whitebox": ["building-block": ["state", "superseded-by"]],
        "deployment-diagram": ["building-block": ["state", "superseded-by"], "deployment-node": ["technology"]],
        // an Agile feature under a use case takes the goals of the use case (`parent`), enablers are found by `lane`
        "goal-coverage": ["functional-requirement": ["parent"]],
        // the goal and epic map draws the hierarchy (`parent`, `order`) and the enabler group (`lane`)
        "goal-tree": ["functional-requirement": ["lane", "order", "parent"]],
    ]

    /// Types the code reads that the projection page does not name at all.
    static let undeclaredTypes: [String: Set<String>] = [
        // a step names stakeholders and interfaces besides blocks
        "sequence-diagram": ["stakeholder", "external-interface"],
        // the breakdown diagram of a requirement lists the blocks that name it in `drivers`
        "story-map": ["building-block"],
        // the neighbours of a term in the network
        "terminology-graph": ["building-block", "external-interface", "goal", "stakeholder"],
    ]

    /// What the metamodel declares: type name to field names, from the `reads:` of a projection page.
    private func declared(_ name: String, in metamodel: Metamodel) -> [String: Set<String>]? {
        guard let page = metamodel.projections.first(where: { $0.name == name }) else { return nil }
        var result: [String: Set<String>] = [:]
        for entry in page.entries["reads"] ?? [] {
            guard let type = entry["type"] else { continue }
            let fields = (entry["fields"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            result[type, default: []].formUnion(fields)
        }
        return result
    }

    @Test(arguments: Fixture.names)
    func theConstantsOfEveryProjectionAreDeclaredByItsPageOrListedAsDebt(fixture: String) throws {
        let metamodel = WikiStore(root: try Preflight.open(Fixture.url(fixture))).metamodel
        for declaration in Projections.declarations {
            let page = try #require(declared(declaration.name, in: metamodel), "\(fixture) has no page for \(declaration.name)")
            for read in declaration.reads {
                guard let fields = page[read.type] else {
                    #expect(Self.undeclaredTypes[declaration.name]?.contains(read.type) == true,
                            "\(declaration.name) reads \(read.type), its page does not name the type")
                    continue
                }
                let missing = Set(read.fields).subtracting(fields).subtracting(Self.undeclaredFields[declaration.name]?[read.type] ?? [])
                #expect(missing.isEmpty, "\(declaration.name) reads \(missing.sorted()) of \(read.type), its page does not declare them")
            }
        }
        // an entry of the debt lists that the page declares by now is stale
        for (name, types) in Self.undeclaredFields {
            let page = try #require(declared(name, in: metamodel))
            for (type, fields) in types { #expect(fields.isDisjoint(with: page[type] ?? []), "\(name): \(type) \(fields) is declared by now") }
        }
        for (name, types) in Self.undeclaredTypes {
            let page = try #require(declared(name, in: metamodel))
            #expect(types.isDisjoint(with: page.keys), "\(name): \(types) is declared by now")
        }
    }

    @Test func everyProjectionNamesAPageOfTheFixtures() throws {
        let metamodel = WikiStore(root: try Preflight.open(Fixture.url("basic"))).metamodel
        let projections = try projections("basic")
        #expect(projections.available == metamodel.projections.map(\.name))
        for declaration in Projections.declarations { #expect(projections.available.contains(declaration.name), "\(declaration.name)") }
    }

    @Test func aWikiThatTailorsAProjectionAwayDoesNotGetIt() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("goals", "GOAL-001-v", "V", "accepted", [("stereotype", "vision")])
        try wiki.page("goals", "GOAL-002-o", "O", "accepted", [("stereotype", "objective")])
        try wiki.page("functional-requirements", "FR-001-a", "A", "accepted",
                      [("notation", "agile"), ("level", "epic"), ("goal", "[\"[[GOAL-002-o]]\"]"), ("priority", "Must")])
        try wiki.page("functional-requirements", "FR-002-b", "B", "accepted",
                      [("notation", "agile"), ("level", "story"), ("parent", "[\"[[FR-001-a]]\"]")])
        let full = try wiki.projections()
        #expect(!full.hierarchy().isEmpty && !full.backlog().isEmpty && !full.goalMatrix().goals.isEmpty)
        #expect(full.mermaid("goals") != nil && full.mermaid("page-FR-001") != nil)

        let projectionPages = wiki.url.appending(path: "_system/metamodel/projections")
        for name in ["proj-story-map.md", "proj-goal-coverage.md", "proj-goal-tree.md", "proj-backlog-ranking.md"] {
            try FileManager.default.removeItem(at: projectionPages.appending(path: name))
        }
        let tailored = try wiki.projections()
        #expect(!tailored.available.contains("story-map") && tailored.available.contains("whitebox"))
        #expect(tailored.hierarchy().isEmpty)
        #expect(tailored.storyMap().backbone.isEmpty)
        #expect(tailored.goalMatrix().goals.isEmpty)
        #expect(tailored.backlog().isEmpty)
        #expect(tailored.mermaid("goals") == nil)
        #expect(tailored.mermaid("story-map") == nil)
        #expect(tailored.mermaid("page-FR-001") == nil)
        // what no projection page covers stays
        #expect(!tailored.detail(of: "FR-001").children.isEmpty)
        #expect(tailored.graph("metamodel-graph") != nil)
    }

    @Test func aTailoredWikiLosesTheTermNetworkAndTheDiagramsOfItsPages() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        try wiki.page("domain-terms", "DT-001-a", "A", "accepted", [("stereotype", "entity")])
        let projectionPages = wiki.url.appending(path: "_system/metamodel/projections")
        #expect(try wiki.projections().graph("term-network") != nil && wiki.projections().mermaid("data-model") != nil)
        for name in ["proj-terminology-graph.md", "proj-entity-diagram.md"] {
            try FileManager.default.removeItem(at: projectionPages.appending(path: name))
        }
        let tailored = try wiki.projections()
        #expect(tailored.graph("term-network") == nil && tailored.graph("term-network-related") == nil)
        #expect(tailored.mermaid("data-model") == nil)
        #expect(tailored.termNeighbourhood(of: "DT-001").nodes.isEmpty)
        #expect(tailored.termNetwork(layers: ["stakeholder"]).nodes.isEmpty)
    }
}
