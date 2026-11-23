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
        // The domain terms type declares two projections, both drawn as graphs in the web view.
        let terms = ProjectionHost.modes(for: try section(containing: "domain-terms", in: s), metamodel: s.metamodel)
        #expect(terms == ["list", "terminology-graph", "entity-diagram"])
        let goals = ProjectionHost.modes(for: try section(containing: "goals", in: s), metamodel: s.metamodel)
        #expect(goals == ["list", "goal-tree", "goal-coverage"])
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
        let epic = try #require(data.outline[0].item.ref)
        #expect(OutlineNode.flatten(data.outline, collapsed: [epic]).count == 2)
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
        let restored = ListModel(session: s, section: fr, state: ListState(mode: "story-map"))
        #expect(restored.state.mode == "story-map")
        let dropped = ListModel(session: s, section: fr, state: ListState(mode: "no-such-mode"))
        #expect(dropped.state.mode == ListModel.listMode)
        // The section is not selected yet: the choice is kept in the model's state only.
        model.choose("backlog-ranking")
        #expect(s.mode == ListModel.listMode && model.currentMode == "backlog-ranking" && model.state.mode == "backlog-ranking")
        s.select(section: fr.id)
        let shown = ListModel(session: s, section: fr)
        shown.choose("story-map")
        #expect(s.mode == "story-map" && shown.currentMode == "story-map" && shown.state.mode == "story-map")
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
        for number in 10..<68 {
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
        // 2 epics of the fixture and 58 generated ones, 7 objectives.
        #expect(data.matrix.columns.count == 60 && data.matrix.rows.count == 7)
        #expect(data.matrix.rows.allSatisfy { $0.marks.count == 60 })
        var marked = 0
        for row in data.matrix.rows { marked += row.marks.filter { $0 }.count }
        #expect(marked == 59)
        // The render draws the content without its scroll views: an offscreen render does not draw scroll view content.
        // The scroll path is not rendered here.
        let started = ContinuousClock.now
        let view = GoalMatrixView(model: data.matrix, selected: nil, onSelect: { _ in }).content(scrolls: false)
            .frame(width: 1000, height: 600)
        let renderer = ImageRenderer(content: view)
        let image = renderer.cgImage
        #expect(image != nil)
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    // MARK: Fix round 1

    @Test func selectingInsideAProjectionKeepsSectionAndMode() async throws {
        let s = try await session("basic")
        let fr = try section(containing: "functional-requirements", in: s)
        s.select(section: fr.id)
        s.select(mode: "goal-coverage")
        let goal = PageRef(folder: "goals", stem: "GOAL-002-faster-lending")
        let other = PageRef(folder: "stakeholders", stem: "STK-001-librarian")
        for ref in [goal, other] {
            s.projections.select(ref)
            #expect(s.selectedSection == fr.id && s.mode == "goal-coverage" && s.selectedPage == ref)
            s.back()
            #expect(s.selectedSection == fr.id && s.mode == "goal-coverage" && s.selectedPage == nil)
        }
        // A page that does not exist changes nothing.
        s.projections.select(PageRef(folder: "goals", stem: "nothing"))
        #expect(s.selectedPage == nil)
    }

    @Test func aBuildingBlockOfAnotherSectionOpensInTheProjection() async throws {
        let s = try await session("arc42")
        let fr = try section(containing: "functional-requirements", in: s)
        s.select(section: fr.id)
        let mode = try #require(ProjectionHost.modes(for: fr, metamodel: s.metamodel).dropFirst().first)
        s.select(mode: mode)
        let block = try #require(s.store.pages(in: "building-blocks").first)
        s.projections.select(block.ref)
        #expect(s.selectedSection == fr.id && s.mode == mode && s.selectedPage == block.ref)
        s.back()
        #expect(s.mode == mode && s.selectedPage == nil)
    }

    @Test func aTourStepDoesNotChangeTheRememberedMode() async throws {
        let s = try await session("basic")
        let fr = try section(containing: "functional-requirements", in: s)
        let goals = try section(containing: "goals", in: s)
        s.select(section: fr.id)
        s.select(mode: "story-map")
        s.showUnrecorded(section: goals.id, page: nil)
        s.showUnrecorded(section: fr.id, page: nil)
        #expect(s.mode == "story-map")
        s.showUnrecorded(section: fr.id, page: PageRef(folder: "functional-requirements", stem: "FR-002-checkout"))
        #expect(s.mode == "story-map")
        s.select(section: goals.id)
        s.select(section: fr.id)
        #expect(s.mode == "story-map")
    }

    @Test func aModeTheSectionNoLongerOffersShowsTheList() async throws {
        let wiki = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: wiki.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(wiki))
        let fr = try section(containing: "functional-requirements", in: s)
        s.select(section: fr.id)
        s.select(mode: "story-map")
        try FileManager.default.removeItem(at: wiki.appending(path: "_system/metamodel/projections/proj-story-map.md"))
        s.replace(with: LoadedWiki(root: try Preflight.open(wiki)))
        #expect(s.mode == ListModel.listMode)
        s.back()
        s.forward()
        #expect(s.mode == ListModel.listMode && !s.showsProjection)
        #expect(ProjectionHost.modes(for: try section(containing: "functional-requirements", in: s), metamodel: s.metamodel) == ["list", "backlog-ranking", "goal-coverage"])
    }

    @Test func aModeTheAppDoesNotDrawIsNotAProjection() async throws {
        #expect(ProjectionHost.nativeProjections == ["story-map", "goal-coverage", "backlog-ranking"] + GraphModes.all)
        // The projections of a type that have no drawing, such as a list of what governs a block, are no mode.
        #expect(!ProjectionHost.nativeProjections.contains("governed-by") && !ProjectionHost.nativeProjections.contains("sequence-diagram"))
        let s = try await session("basic")
        #expect(!s.showsProjection)
        s.select(section: try section(containing: "functional-requirements", in: s).id)
        #expect(!s.showsProjection)
        s.select(mode: "story-map")
        #expect(s.showsProjection)
    }

    @Test func reloadWhileAProjectionShows() async throws {
        let wiki = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: wiki.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(wiki))
        s.select(section: try section(containing: "functional-requirements", in: s).id)
        s.select(mode: "story-map")
        let gone = PageRef(folder: "functional-requirements", stem: "FR-002-checkout")
        s.select(page: gone)
        let first = try await loaded(s)
        #expect(first.storyMap.allIDs.contains("FR-002"))
        try FileManager.default.removeItem(at: wiki.appending(path: "wiki/functional-requirements/FR-002-checkout.md"))
        s.replace(with: LoadedWiki(root: try Preflight.open(wiki)))
        #expect(!s.projections.isCurrent)
        // Old data and the new store must not be mixed: the detail waits for the new data.
        let early = await s.projections.detail(of: gone)
        #expect(early.isEmpty)
        let second = try await loaded(s)
        #expect(second.revision == 1 && s.projections.isCurrent)
        #expect(!second.storyMap.allIDs.contains("FR-002"))
        #expect(s.selectedPage == gone && s.store.page(gone) == nil)
        let detail = await s.projections.detail(of: gone)
        #expect(detail.isEmpty)
    }

    @Test func aStaleResultIsDropped() async throws {
        let s = try await session("basic")
        let gate = ProjectionGate()
        let model = ProjectionsModel(session: s) { store, metamodel, agreedOnly, revision in
            await gate.pass()
            return ProjectionData.build(store: store, metamodel: metamodel, agreedOnly: agreedOnly, revision: revision)
        }
        let first = Task { await model.load() }
        for _ in 0..<3000 where await gate.waiting == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await gate.waiting == 1)
        s.agreedOnly = true
        let second = Task { await model.load() }
        for _ in 0..<3000 where await gate.waiting < 2 { try await Task.sleep(for: .milliseconds(10)) }
        await gate.release()
        await first.value
        await second.value
        let data = try #require(model.data)
        #expect(data.agreedOnly && !data.backlog.map(\.item.id).contains("FR-006"))
        #expect(model.isCurrent)
    }

    @Test func backAfterDeselectingThePage() async throws {
        let s = try await session("basic")
        s.select(section: try section(containing: "functional-requirements", in: s).id)
        s.select(mode: "story-map")
        let ref = PageRef(folder: "functional-requirements", stem: "FR-002-checkout")
        s.select(page: ref)
        s.deselectPage()
        #expect(s.selectedPage == nil)
        s.back()
        #expect(s.selectedPage == ref && s.mode == "story-map")
        s.back()
        #expect(s.selectedPage == nil && s.mode == "story-map")
        s.forward()
        s.forward()
        #expect(s.selectedPage == nil && s.mode == "story-map")
    }

    private func page(_ id: String, _ stem: String, title: String, extra: String) -> String {
        """
        ---
        id: \(id)
        type: functional-requirement
        title: \(title)
        status: accepted
        \(extra)
        ---
        Text.
        """
    }

    @Test func duplicateIdsKeepEveryPageOnce() async throws {
        let wiki = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: wiki.deletingLastPathComponent()) }
        let dir = wiki.appending(path: "wiki/functional-requirements")
        let extra = "notation: agile\nlevel: story\nparent: [\"[[FR-002-checkout]]\"]\npriority: Could\nrelease: v1\nlane: backbone\norder: 9\ngoal: []"
        try page("FR-003", "x", title: "Same id as the scan story", extra: extra).write(to: dir.appending(path: "FR-003-twin.md"), atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(wiki))
        let data = try await loaded(s)
        let keys = OutlineNode.flatten(data.outline, collapsed: []).map(\.node.key)
        #expect(keys.count == 7 && Set(keys).count == 7)
        let refs = data.backlog.compactMap(\.item.ref)
        #expect(refs.count == 7 && Set(refs).count == 7)
        #expect(data.backlog.map(\.item.key).count == Set(data.backlog.map(\.item.key)).count)
        #expect(data.storyMap.allIDs.filter { $0 == "FR-003" }.count >= 2)
    }

    @Test func emptyLevelAndEmptyReleaseAreWords() async throws {
        let wiki = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: wiki.deletingLastPathComponent()) }
        let dir = wiki.appending(path: "wiki/functional-requirements")
        try page("FR-020", "x", title: "A requirement in another notation", extra: "notation: ears\npriority: Could\norder: 20")
            .write(to: dir.appending(path: "FR-020-ears.md"), atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(wiki))
        let data = try await loaded(s)
        let row = try #require(data.backlog.first { $0.item.id == "FR-020" })
        #expect(row.level.isEmpty && row.release.isEmpty)
        #expect(!row.accessibilityLabel.contains(", ,") && !row.accessibilityLabel.hasSuffix(","))
        let node = try #require(data.outline.first { $0.item.id == "FR-020" })
        #expect(node.level.isEmpty)
        #expect(ProjectionLabel.release("") == "No release" && ProjectionLabel.release("  ") == "No release")
        #expect(ProjectionLabel.release("v1") == "v1")
    }
}

/// Holds computations until `release()`. A held call ends by itself after 30 seconds, so a failing test does not hang.
private actor ProjectionGate {
    private var open = false
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var next = 0
    var waiting: Int { continuations.count + finished }
    private var finished = 0

    func pass() async {
        if open { return }
        next += 1
        let id = next
        Task { [self] in
            try? await Task.sleep(for: .seconds(30))
            stop(id)
        }
        if id == 1 {
            await withCheckedContinuation { continuations[id] = $0 }
        } else {
            finished += 1
        }
    }

    private func stop(_ id: Int) {
        continuations.removeValue(forKey: id)?.resume()
    }

    func release() {
        open = true
        for c in continuations.values { c.resume() }
        continuations = [:]
    }
}
