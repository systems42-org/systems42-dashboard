import Foundation
import SwiftUI
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor
private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

/// Loads the projections of the session's current revision and records an issue when it takes longer than 30 seconds.
@MainActor
private func loaded(_ s: WikiSession, agreedOnly: Bool = false) async throws -> ProjectionData {
    s.agreedOnly = agreedOnly
    let model = s.projections
    let started = ContinuousClock.now
    await model.load()
    if ContinuousClock.now - started > .seconds(30) { Issue.record("loading the projections took more than 30 seconds") }
    return try #require(model.data)
}

@MainActor private func section(containing folder: String, in s: WikiSession) throws -> WikiSection {
    try #require(s.metamodel.sections.first { $0.folders.contains(folder) })
}

@MainActor @Suite struct ProjectionModelTests {
    @Test func modesComeFromTheMetamodel() async throws {
        let s = try await session("basic")
        let requirements = ProjectionHost.modes(for: try section(containing: "functional-requirements", in: s), metamodel: s.metamodel)
        #expect(requirements == ["list", "story-map", "backlog-ranking", "goal-coverage"])
        // The domain terms type declares two projections, both drawn as graphs by a later issue.
        let terms = ProjectionHost.modes(for: try section(containing: "domain-terms", in: s), metamodel: s.metamodel)
        #expect(terms == ["list"])
        let goals = ProjectionHost.modes(for: try section(containing: "goals", in: s), metamodel: s.metamodel)
        #expect(goals == ["list", "goal-coverage"])
    }

    @Test func aTailoredWikiOffersOnlyWhatItDeclares() async throws {
        let s = try await session("tailored")
        for section in s.metamodel.sections {
            let declared = Set(section.types.compactMap { s.metamodel.type(named: $0) }.flatMap(\.projections))
            let offered = Set(s.metamodel.projections.map(\.name))
            for mode in ProjectionHost.modes(for: section, metamodel: s.metamodel) where mode != ListModel.listMode {
                #expect(declared.contains(mode) && offered.contains(mode), "\(section.id) \(mode)")
            }
        }
    }

    @Test func storyMapShowsEveryRequirementOnce() async throws {
        let data = try await loaded(try await session("basic"))
        #expect(data.storyMap.allIDs.sorted() == ["FR-001", "FR-002", "FR-003", "FR-004", "FR-005", "FR-006"])
    }

    @Test func storyMapRowsAreReleases() async throws {
        // FR-006 is an epic in `unscheduled` with no card, and the core adds a row only for a release with a card.
        let data = try await loaded(try await session("basic"))
        #expect(data.storyMap.releases == ["v1"])
        #expect(data.storyMap.columns.map(\.item.id) == ["FR-001", "FR-006"])
        #expect(data.storyMap.cards(column: 0, release: "v1").map(\.item.id) == ["FR-002", "FR-003", "FR-005", "FR-004"])
    }

    @Test func matrixMarksMatchTheCore() async throws {
        let s = try await session("basic")
        let data = try await loaded(s)
        let core = Projections(store: s.store, metamodel: s.metamodel, agreedOnly: false).goalMatrix()
        #expect(!data.matrix.rows.isEmpty)
        for row in data.matrix.rows {
            #expect(row.marks.count == data.matrix.columns.count)
            for (index, column) in data.matrix.columns.enumerated() {
                #expect(row.marks[index] == core.marked(goal: row.item.id, column: column.item.id), "\(row.item.id) \(column.item.id)")
            }
        }
        #expect(data.matrix.rows.first?.marks == [true, false])
    }

    @Test func gapAndUntracedAreDistinct() async throws {
        let wiki = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: wiki.deletingLastPathComponent()) }
        try """
        ---
        id: GOAL-003
        type: goal
        title: Unserved Goal
        status: accepted
        stereotype: objective
        parent: []
        ---
        Nothing serves it.
        """.write(to: wiki.appending(path: "wiki/goals/GOAL-003-unserved.md"), atomically: true, encoding: .utf8)
        try """
        ---
        id: FR-007
        type: functional-requirement
        title: Untraced Epic
        status: accepted
        notation: agile
        level: epic
        parent: []
        priority: Should
        release: v1
        lane: backbone
        order: 7
        goal: []
        ---
        Names no goal.
        """.write(to: wiki.appending(path: "wiki/functional-requirements/FR-007-untraced.md"), atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(wiki))
        let data = try await loaded(s)
        let gap = try #require(data.matrix.rows.first { $0.item.id == "GOAL-003" })
        let served = try #require(data.matrix.rows.first { $0.item.id == "GOAL-002" })
        let untraced = try #require(data.matrix.columns.first { $0.item.id == "FR-007" })
        let traced = try #require(data.matrix.columns.first { $0.item.id == "FR-001" })
        #expect(gap.gap && !served.gap)
        #expect(untraced.untraced && !traced.untraced)
        #expect(gap.accessibilityLabel.contains("no requirement serves this goal"))
        #expect(!served.accessibilityLabel.contains("no requirement serves this goal"))
        #expect(untraced.accessibilityLabel.contains("names no goal"))
        #expect(!traced.accessibilityLabel.contains("names no goal"))
        #expect(gap.accessibilityLabel != untraced.accessibilityLabel)
    }

    @Test func everyMarkIsAlsoText() async throws {
        let data = try await loaded(try await session("basic"))
        for row in data.matrix.rows {
            let named = Set(row.serving.map(\.id))
            for (index, column) in data.matrix.columns.enumerated() where row.marks[index] {
                #expect(named.contains(column.item.id), "\(row.item.id) \(column.item.id)")
            }
        }
        for row in data.matrix.rows {
            for (index, column) in data.matrix.columns.enumerated() {
                let label = data.matrix.cellLabel(row: row, column: index)
                #expect(label.contains(row.item.id) && label.contains(column.item.id))
                #expect(label.contains(row.marks[index] ? "serves" : "does not serve"))
            }
        }
    }

    @Test func agreedOnlyHidesDrafts() async throws {
        let data = try await loaded(try await session("basic"), agreedOnly: true)
        let everywhere = data.storyMap.allIDs + data.matrix.columns.map(\.item.id) + data.matrix.rows.flatMap { $0.serving.map(\.id) }
            + data.outline.flatMap(\.allIDs) + data.backlog.map(\.item.id)
        #expect(!everywhere.contains("FR-006"))
        #expect(data.backlog.count == 5)
        let all = try await loaded(try await session("basic"))
        #expect(all.backlog.count == 6)
        #expect(all.backlog.map(\.item.id).contains("FR-006"))
    }

    @Test func selectionOpensThePage() async throws {
        let s = try await session("basic")
        let data = try await loaded(s)
        let card = try #require(data.storyMap.cards(column: 0, release: "v1").first)
        s.projections.select(try #require(card.item.ref))
        #expect(s.selectedPage == card.item.ref)
        s.projections.select(try #require(data.backlog.last?.item.ref))
        #expect(s.selectedPage == data.backlog.last?.item.ref)
    }

    @Test func emptyWikiShowsAHint() async throws {
        let data = try await loaded(try await session("domain-model"))
        #expect(data.storyMap.isEmpty && data.matrix.isEmpty && data.outline.isEmpty && data.backlog.isEmpty)
        #expect(!ProjectionHint.text(for: ProjectionHost.storyMapMode).isEmpty)
        #expect(!ProjectionHint.text(for: ProjectionHost.matrixMode).isEmpty)
        #expect(!ProjectionHint.text(for: ProjectionHost.backlogMode).isEmpty)
    }

    @Test func hierarchyHoldsEveryRequirementOnceAndFlattens() async throws {
        let data = try await loaded(try await session("basic"))
        #expect(data.outline.flatMap(\.allIDs).sorted() == ["FR-001", "FR-002", "FR-003", "FR-004", "FR-005", "FR-006"])
        let flat = OutlineNode.flatten(data.outline, collapsed: [])
        #expect(flat.count == 6)
        #expect(Set(flat.map(\.node.key)).count == 6)
        let collapsed = OutlineNode.flatten(data.outline, collapsed: [data.outline[0].key])
        #expect(collapsed.count == 2)
    }

    @Test func detailNamesChildrenAndBuildingBlocks() async throws {
        let s = try await session("basic")
        let data = try await loaded(s)
        let epic = try #require(s.store.pages(in: "functional-requirements").first { $0.id == "FR-001" })
        let detail = await s.projections.detail(of: epic.ref)
        #expect(detail.children.map(\.id).sorted() == ["FR-002", "FR-005"])
        #expect(detail.buildingBlocks.isEmpty)
        #expect(data.projections.detail(of: "FR-001").children.count == detail.children.count)
    }

    @Test func aNewRevisionComputesAgain() async throws {
        let s = try await session("basic")
        let first = try await loaded(s)
        s.replace(with: LoadedWiki(root: try Preflight.open(Fixture.url("basic"))))
        let second = try await loaded(s)
        #expect(first.revision == 0 && second.revision == 1)
    }

    @Test func modeIsPartOfThePlaceAndRemembered() async throws {
        let s = try await session("basic")
        let fr = try section(containing: "functional-requirements", in: s)
        let goals = try section(containing: "goals", in: s)
        s.select(section: fr.id)
        s.select(mode: "story-map")
        #expect(s.mode == "story-map")
        s.select(section: goals.id)
        #expect(s.mode == ListModel.listMode)
        s.select(section: fr.id)
        #expect(s.mode == "story-map")
        s.select(mode: "backlog-ranking")
        s.back()
        #expect(s.mode == "story-map")
        s.forward()
        #expect(s.mode == "backlog-ranking")
        s.select(mode: "no-such-mode")
        #expect(s.mode == "backlog-ranking")
        // A mode the section does not offer is not taken.
        s.select(section: goals.id)
        s.select(mode: "backlog-ranking")
        #expect(s.mode == ListModel.listMode)
    }

    @Test func selectingAPageKeepsTheMode() async throws {
        let s = try await session("basic")
        let fr = try section(containing: "functional-requirements", in: s)
        s.select(section: fr.id)
        s.select(mode: "story-map")
        let ref = PageRef(folder: "functional-requirements", stem: "FR-002-checkout")
        s.select(page: ref)
        #expect(s.mode == "story-map" && s.selectedPage == ref)
        s.deselectPage()
        #expect(s.selectedPage == nil && s.mode == "story-map")
    }

    @Test func listModelOffersTheModes() async throws {
        let s = try await session("basic")
        let fr = try section(containing: "functional-requirements", in: s)
        let model = ListModel(session: s, section: fr)
        #expect(model.modes == ["list", "story-map", "backlog-ranking", "goal-coverage"])
        model.choose("backlog-ranking")
        #expect(model.currentMode == "backlog-ranking" || s.selectedSection != fr.id)
        let restored = ListModel(session: s, section: fr, state: ListState(mode: "story-map"))
        #expect(restored.state.mode == "story-map")
        let dropped = ListModel(session: s, section: fr, state: ListState(mode: "no-such-mode"))
        #expect(dropped.state.mode == ListModel.listMode)
    }

    @Test func matrixWithSixtyColumnsRenders() async throws {
        let wiki = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: wiki.deletingLastPathComponent()) }
        for goal in 3...8 {
            try """
            ---
            id: GOAL-\(String(format: "%03d", goal))
            type: goal
            title: Goal number \(goal)
            status: accepted
            stereotype: objective
            parent: []
            ---
            """.write(to: wiki.appending(path: "wiki/goals/GOAL-\(String(format: "%03d", goal))-goal.md"), atomically: true, encoding: .utf8)
        }
        for number in 10..<70 {
            let goal = "GOAL-\(String(format: "%03d", 3 + number % 6))"
            try """
            ---
            id: FR-\(number)
            type: functional-requirement
            title: Generated epic number \(number) with a rather long title that has to be cut
            status: accepted
            notation: agile
            level: epic
            parent: []
            priority: Should
            release: v1
            lane: backbone
            order: \(number)
            goal: ["[[\(goal)-goal]]"]
            ---
            """.write(to: wiki.appending(path: "wiki/functional-requirements/FR-\(number)-generated.md"), atomically: true, encoding: .utf8)
        }
        let s = await WikiSession.open(try Preflight.open(wiki))
        let data = try await loaded(s)
        #expect(data.matrix.columns.count >= 60 && data.matrix.rows.count >= 7)
        let started = ContinuousClock.now
        let view = GoalMatrixView(model: data.matrix, selected: nil, onSelect: { _ in }).content(scrolls: false)
            .frame(width: 1000, height: 600)
        let renderer = ImageRenderer(content: view)
        let image = renderer.cgImage
        #expect(image != nil)
        #expect(ContinuousClock.now - started < .seconds(30))
    }
}
