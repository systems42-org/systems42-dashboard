import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

/// A graph or matrix as JSON text with sorted keys, so two values compare by content.
private func canonical(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    return String(decoding: data, as: UTF8.self)
}

private func canonical(_ graph: Graph) throws -> String {
    try canonical(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)))
}

/// What `goal-matrix.json` holds, written from the public data of the matrix.
private func matrixJSON(_ matrix: GoalMatrix) -> [String: Any] {
    let columns: [[String: Any]] = matrix.columns.map { column in
        ["id": column.id, "status": column.status, "enabler": matrix.enablers.contains { $0.id == column.id },
         "no_goal": matrix.untraced.contains(column.id)]
    }
    var rows: [String: Any] = [:]
    for goal in matrix.goals {
        let serves = matrix.columns.filter { matrix.marked(goal: goal.id, column: $0.id) }.map(\.id)
        rows[goal.id] = [
            "status": goal.status, "gap": matrix.gaps.contains(goal.id), "gap_accepted": matrix.acceptedGaps.contains(goal.id),
            "serves": serves, "served_by": Array(Set(matrix.servedWithoutColumn(goal: goal.id).map(\.id))).sorted(),
        ] as [String: Any]
    }
    return ["columns": columns, "rows": rows]
}

@Suite struct GoldenProjectionTests {
    @Test(arguments: Fixture.names)
    func mermaidMatchesGolden(fixture: String) throws {
        let projections = try projections(fixture)
        var checked = 0
        for file in Golden.diagrams(fixture) where file.hasSuffix(".mmd") {
            let name = String(file.dropLast(".mmd".count))
            let want = try Golden.text(fixture, "diagrams/\(file)")
            checked += 1
            guard let got = projections.mermaid(name) else {
                Issue.record("\(fixture): no projection for \(file)")
                continue
            }
            // The golden file is the dashboard's text with one newline at the end.
            let same = got + "\n" == want
            #expect(same, "\(fixture)/\(file) differs, got:\n\(got)\nwant:\n\(want)")
        }
        #expect(checked == Golden.diagrams(fixture).filter { $0.hasSuffix(".mmd") }.count)
    }

    @Test(arguments: Fixture.names)
    func graphsMatchGolden(fixture: String) throws {
        let projections = try projections(fixture)
        var checked = 0
        for file in Golden.diagrams(fixture) where file.hasSuffix(".json") {
            let name = String(file.dropLast(".json".count))
            let want = try canonical(Golden.json(fixture, "diagrams/\(file)"))
            checked += 1
            let got: String
            if name == "goal-matrix" {
                got = try canonical(matrixJSON(projections.goalMatrix()))
            } else if name.hasPrefix("page-"), name.hasSuffix("-ego") {
                let id = String(name.dropFirst("page-".count).dropLast("-ego".count))
                got = try canonical(projections.termNeighbourhood(of: id))
            } else if let graph = projections.graph(name) {
                got = try canonical(graph)
            } else {
                Issue.record("\(fixture): no projection for \(file)")
                continue
            }
            #expect(got == want, "\(fixture)/\(file) differs, got:\n\(got)\nwant:\n\(want)")
        }
        #expect(checked == Golden.diagrams(fixture).filter { $0.hasSuffix(".json") }.count)
    }

    @Test func goldenFolderIsNotEmpty() {
        #expect(Fixture.names.allSatisfy { !Golden.diagrams($0).isEmpty })
    }
}

@Suite struct HierarchyTests {
    private func flatten(_ nodes: [TreeNode]) -> [TreeNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    @Test func everyRequirementOnceUnderItsParent() throws {
        let store = WikiStore(root: try Preflight.open(Fixture.url("basic")))
        let projections = Projections(store: store, metamodel: store.metamodel, agreedOnly: false)
        let tree = projections.hierarchy()
        let all = flatten(tree)
        #expect(all.map(\.id).sorted() == ["FR-001", "FR-002", "FR-003", "FR-004", "FR-005", "FR-006"])
        func check(_ node: TreeNode, parent: TreeNode?) {
            let ref = node.ref.map { store.linksFrom($0)["parent"] ?? [] } ?? []
            #expect(ref == (parent?.ref.map { [$0] } ?? []), "\(node.id)")
            node.children.forEach { check($0, parent: node) }
        }
        tree.forEach { check($0, parent: nil) }
        #expect(tree.map(\.id) == ["FR-001", "FR-006"])
    }

    @Test func detailListsChildrenAndBlocks() throws {
        let store = WikiStore(root: try Preflight.open(Fixture.url("arc42")))
        let projections = Projections(store: store, metamodel: store.metamodel, agreedOnly: false)
        for id in ["FR-001", "UC-001"] {
            let page = try #require(store.page(id: id))
            let detail = projections.detail(of: id)
            let named = store.linksTo(page.ref)
            #expect(Set(detail.children.map(\.ref)) == Set(named["parent"] ?? []))
            let blocks = (named["drivers"] ?? []).filter { $0.folder == "building-blocks" }
            #expect(detail.buildingBlocks.map(\.ref) == blocks.sorted { ($0.stem) < ($1.stem) })
            #expect(detail.buildingBlocks.map(\.id) == ["BB-001"])
        }
        let basic = try self.basicProjections()
        #expect(basic.detail(of: "FR-002").children.map(\.id) == ["FR-003", "FR-004"])
        #expect(basic.detail(of: "FR-002").buildingBlocks.isEmpty)
        #expect(basic.detail(of: "no-such").children.isEmpty)
    }

    private func basicProjections() throws -> Projections { try projections("basic") }
}

@Suite struct StoryMapAndBacklogTests {
    @Test func storyMapReleases() throws {
        let map = try projections("basic").storyMap()
        #expect(map.releases == ["v1", "unscheduled"])
        #expect(map.backbone.map(\.id) == ["FR-001", "FR-006"])
        #expect(map.backbone.first { $0.id == "FR-006" }?.release == "unscheduled")
        #expect(map.cards(under: "FR-001", release: "v1").map(\.id) == ["FR-002", "FR-003", "FR-004", "FR-005"])
        #expect(map.cards(under: "FR-001", release: "unscheduled").isEmpty)
        #expect(map.cards(under: "no-such", release: "v1").isEmpty)
    }

    @Test func backlogOrder() throws {
        #expect(try projections("basic").backlog().map(\.id) == ["FR-001", "FR-002", "FR-003", "FR-005", "FR-004", "FR-006"])
    }

    @Test func backlogSortsByPriorityThenReleaseThenOrderThenId() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        func fr(_ n: Int, _ priority: String, _ release: String, _ order: String) throws {
            let stem = "FR-00\(n)-x"
            try wiki.page("functional-requirements", stem, "FR \(n)", "draft",
                [("notation", "agile"), ("level", "story"), ("priority", priority), ("release", release), ("order", order)])
        }
        try fr(1, "Could", "v1", "1")
        try fr(2, "Must", "unscheduled", "1")
        try fr(3, "Must", "v1", "5")
        try fr(4, "Must", "v1", "2")
        try fr(5, "", "v1", "1")
        try fr(6, "Won't", "v1", "1")
        try fr(7, "Must", "v1", "2")
        try fr(8, "Should", "v1", "")
        #expect(try wiki.projections().backlog().map(\.id) == ["FR-004", "FR-007", "FR-003", "FR-002", "FR-008", "FR-001", "FR-006", "FR-005"])
    }
}

@Suite struct TermNetworkTests {
    @Test func termLinksComeFromRelatedOnly() throws {
        let store = WikiStore(root: try Preflight.open(Fixture.url("domain-model")))
        let projections = Projections(store: store, metamodel: store.metamodel, agreedOnly: false)
        let graph = try #require(projections.graph("term-network-related"))
        var seen = Set<Set<String>>()
        for edge in graph.edges where edge.data["cross"]?.bool == false {
            #expect(edge.data["kind"]?.string == "related")
            #expect(seen.insert([edge.source, edge.target]).inserted, "a pair appears once, whatever the direction")
        }
        // Every edge is named by `related:` on at least one of its two pages.
        for edge in graph.edges {
            let source = try #require(store.page(PageRef(folder: "domain-terms", stem: edge.source)))
            let target = store.page(PageRef(folder: "domain-terms", stem: edge.target))
            let named = (store.linksFrom(source.ref)["related"] ?? []).contains { $0.stem == edge.target }
                || (target.map { (store.linksFrom($0.ref)["related"] ?? []).contains { $0.stem == edge.source } } ?? false)
            #expect(named, "\(edge.source) to \(edge.target)")
        }
        // The aliases of the all view hold the same pairs, and the structured edges come on top.
        let all = try #require(projections.graph("terms"))
        #expect(all.edges.count >= graph.edges.count)
        let structured = try #require(projections.graph("term-network-structured"))
        #expect(structured.edges.allSatisfy { $0.data["kind"]?.string != "related" })
    }

    @Test func termLayersAddOnlyNeighbours() throws {
        let store = WikiStore(root: try Preflight.open(Fixture.url("basic")))
        let projections = Projections(store: store, metamodel: store.metamodel, agreedOnly: false)
        let all = try #require(projections.graph("term-network"))
        let termsOnly = projections.termNetwork(layers: [])
        #expect(termsOnly.nodes.allSatisfy { $0.data["core"]?.bool == true })
        #expect(termsOnly.nodes.count == all.nodes.filter { $0.data["core"]?.bool == true }.count)
        let withStakeholders = projections.termNetwork(layers: ["stakeholder"])
        let added = withStakeholders.nodes.filter { $0.data["core"]?.bool == false }
        #expect(!added.isEmpty)
        #expect(added.allSatisfy { $0.data["type"]?.string == "STK" })
        let shown = Set(withStakeholders.nodes.map(\.id))
        for node in added {
            let next = withStakeholders.edges.contains { ($0.source == node.id && shown.contains($0.target)) || ($0.target == node.id && shown.contains($0.source)) }
            #expect(next, "\(node.id) is next to a shown term")
        }
        #expect(withStakeholders.edges.allSatisfy { shown.contains($0.source) && shown.contains($0.target) })
    }
}

@Suite struct ProjectionRobustnessTests {
    private func everything(_ projections: Projections) {
        _ = projections.hierarchy()
        _ = projections.detail(of: "X")
        _ = projections.storyMap()
        _ = projections.goalMatrix()
        _ = projections.backlog()
        _ = projections.termNeighbourhood(of: "X")
        for name in ["context", "data-model", "models", "goals", "story-map", "building-blocks", "deployment", "runtime/X", "page-X"] {
            _ = projections.mermaid(name)
        }
        for name in ["terms", "term-network", "term-network-related", "term-network-structured", "metamodel-graph", "metamodel"] {
            _ = projections.graph(name)
        }
    }

    @Test func emptyWikiGivesEmptyProjections() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        let projections = try wiki.projections()
        everything(projections)
        #expect(projections.hierarchy().isEmpty)
        #expect(projections.storyMap().backbone.isEmpty)
        #expect(projections.storyMap().releases.isEmpty)
        #expect(projections.goalMatrix().goals.isEmpty)
        #expect(projections.goalMatrix().columns.isEmpty)
        #expect(projections.backlog().isEmpty)
        #expect(projections.termNeighbourhood(of: "DT-001").nodes.isEmpty)
        #expect(projections.mermaid("story-map") == nil)
        #expect(projections.mermaid("building-blocks") == nil)
        #expect(projections.mermaid("deployment") == nil)
        #expect(projections.mermaid("data-model") == nil)
        #expect(projections.graph("term-network")?.nodes.isEmpty == true)
    }

    @Test func missingMetamodelGivesEmptyProjections() throws {
        let wiki = try TempWiki(metamodel: false)
        defer { wiki.remove() }
        try wiki.page("functional-requirements", "FR-001-a", "A", "draft", [("notation", "agile"), ("level", "epic")])
        let projections = try wiki.projections()
        everything(projections)
        #expect(projections.hierarchy().isEmpty)
        #expect(projections.backlog().isEmpty)
        #expect(projections.goalMatrix().goals.isEmpty)
    }

    @Test func projectionsAreBuiltAndUsedOffTheMainActor() async throws {
        let store = WikiStore(root: try Preflight.open(Fixture.url("basic")))
        let metamodel = store.metamodel
        let roots = await Task.detached {
            Projections(store: store, metamodel: metamodel, agreedOnly: false).hierarchy().count
        }.value
        #expect(roots == 2)
    }

    @Test func hostileWikiGivesProjections() throws {
        let projections = try projections("hostile")
        everything(projections)
        #expect(projections.graph("term-network") != nil)
        #expect(projections.graph("metamodel-graph") != nil)
    }

    @Test func aPageThatIsItsOwnAncestorDoesNotLoop() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        func fr(_ n: Int, _ level: String, parent: String) throws {
            try wiki.page("functional-requirements", "FR-00\(n)-x", "FR \(n)", "draft",
                [("notation", "agile"), ("level", level), ("parent", "[\"[[\(parent)]]\"]")])
        }
        try fr(1, "feature", parent: "FR-002-x")
        try fr(2, "feature", parent: "FR-001-x")
        try fr(3, "story", parent: "FR-003-x")
        try fr(4, "story", parent: "FR-099-missing")
        for (stem, parent) in [("BB-001-a", "BB-002-b"), ("BB-002-b", "BB-001-a"), ("BB-003-c", "BB-003-c")] {
            try wiki.page("building-blocks", stem, stem, "draft", [("parent", "\"[[\(parent)]]\""), ("uses", "[\"[[BB-001-a]]\"]")])
        }
        for (stem, parent) in [("DN-001-a", "DN-002-b"), ("DN-002-b", "DN-001-a")] {
            try wiki.page("deployment-nodes", stem, stem, "draft", [("parent", "\"[[\(parent)]]\""), ("hosts", "[\"[[BB-001-a]]\"]")])
        }
        let projections = try wiki.projections()
        let all = projections.hierarchy()
        func ids(_ nodes: [TreeNode]) -> [String] { nodes.flatMap { [$0.id] + ids($0.children) } }
        #expect(ids(all).sorted() == ["FR-001", "FR-002", "FR-003", "FR-004"])
        #expect(projections.mermaid("building-blocks")?.contains("BB-001") == true)
        #expect(projections.mermaid("deployment")?.contains("DN-001") == true)
        _ = projections.detail(of: "FR-001")
        _ = projections.mermaid("page-FR-001")
        _ = projections.mermaid("page-DN-001")
        _ = projections.mermaid("page-BB-001")
        _ = projections.storyMap()
    }

    @Test func thousandsOfPagesAndDeepChains() throws {
        let wiki = try TempWiki()
        defer { wiki.remove() }
        let n = 3000
        for i in 1...n {
            let stem = "FR-\(String(format: "%04d", i))-x"
            let parent = i == 1 ? "[]" : "[\"[[FR-\(String(format: "%04d", i - 1))-x]]\"]"
            try wiki.page("functional-requirements", stem, "FR \(i)", "draft",
                [("notation", "agile"), ("level", i == 1 ? "epic" : (i == 2 ? "feature" : "story")), ("parent", parent), ("order", "\(i)")])
            let bbParent = i == 1 ? "[]" : "\"[[BB-\(String(format: "%04d", i - 1))-x]]\""
            try wiki.page("building-blocks", "BB-\(String(format: "%04d", i))-x", "BB \(i)", "draft", [("parent", bbParent)])
        }
        let projections = try wiki.projections()
        #expect(projections.hierarchy().count >= 1)
        #expect(projections.backlog().count == n)
        #expect(projections.mermaid("building-blocks") != nil)
        #expect(projections.mermaid("page-FR-0001") != nil)
        _ = projections.storyMap()
        _ = projections.goalMatrix()
    }
}
