import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit
@testable import Systems42UI

@MainActor
private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

@MainActor
private func model(_ fixture: String, folder: String, state: ListState? = nil) async throws -> (WikiSession, ListModel) {
    let s = try await session(fixture)
    let section = try #require(s.metamodel.sections.first { $0.folders.contains(folder) })
    return (s, ListModel(session: s, section: section, state: state))
}

@MainActor private func ids(_ model: ListModel) -> [String] { model.rows.map(\.id) }

private let requirements = "functional-requirements"

@MainActor @Suite struct ListModelTests {
    @Test func defaultPresetOrdersRequirements() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        #expect(ids(m) == ["FR-001", "FR-002", "FR-003", "FR-005", "FR-004", "FR-006"])
        #expect(m.presets.first?.label == "Priority › release › order")
        #expect(m.state.mode == ListModel.listMode)
    }

    @Test func twoColumnSortBreaksTies() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        m.state.sort = [SortKey(field: "release", ascending: false), SortKey(field: "order", ascending: false)]
        #expect(ids(m) == ["FR-004", "FR-005", "FR-001", "FR-002", "FR-003", "FR-006"])
    }

    @Test func enumOrderIsTheMetamodelOrder() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        m.state.sort = [SortKey(field: "priority", ascending: true)]
        #expect(m.rows.map { m.value(of: "priority", in: $0) } == ["Must", "Must", "Must", "Must", "Should", "Could"])
        m.state.sort = [SortKey(field: "priority", ascending: false)]
        #expect(m.rows.map { m.value(of: "priority", in: $0) } == ["Could", "Should", "Must", "Must", "Must", "Must"])
    }

    @Test func statusSortsInLifecycleOrder() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        m.state.sort = [SortKey(field: ListModel.statusField, ascending: true)]
        #expect(ids(m).first == "FR-006")
        m.state.sort = [SortKey(field: ListModel.statusField, ascending: false)]
        #expect(ids(m).last == "FR-006")
    }

    @Test func everyColumnSortsAlone() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        #expect(m.columns.count > 5)
        for column in m.columns {
            for ascending in [true, false] {
                m.state.sort = [SortKey(field: column, ascending: ascending)]
                #expect(m.rows.count == 6, "\(column)")
            }
        }
    }

    @Test func statusFilter() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        m.state.filters = [ListModel.statusField: ["draft"]]
        #expect(ids(m) == ["FR-006"])
    }

    @Test func filtersCombine() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        m.state.filters = [ListModel.statusField: ["accepted"], "priority": ["Must"]]
        #expect(m.rows.count == 4)
        m.state.filters = ["priority": ["Must", "Should"]]
        #expect(m.rows.count == 5)
    }

    @Test func filterOffersMetamodelValues() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        let fields = m.filterFields.map(\.field)
        #expect(fields.first == ListModel.statusField)
        #expect(m.filterFields.first { $0.field == "priority" }?.values == ["Must", "Should", "Could", "Won't"])
        #expect(m.filterFields.first { $0.field == ListModel.statusField }?.values.first == "draft")
    }

    @Test func agreedOnlyApplies() async throws {
        let (s, m) = try await model("basic", folder: requirements)
        s.agreedOnly = true
        #expect(m.rows.count == 5)
        s.agreedOnly = false
        #expect(m.rows.count == 6)
    }

    @Test func issueFiltersOfferCategory() async throws {
        let (_, m) = try await model("search", folder: "issues")
        let fields = m.filterFields.map(\.field)
        #expect(fields.contains("category"))
        #expect(fields.contains("severity"))
        #expect(fields.contains(ListModel.statusField))
        #expect(m.filterFields.first { $0.field == "category" }?.values.isEmpty == false)
    }

    private func restricted() async throws -> (WikiSession, ListModel, SidebarRow) {
        let (s, m) = try await model("search", folder: "issues")
        let row = try #require(s.sidebar.flatMap(\.rows).first { $0.section.folders.contains("stakeholders") })
        return (s, m, row)
    }

    @Test func issueRestrictionShowsExactlyTheCountedIssues() async throws {
        let (s, m, row) = try await restricted()
        let all = ids(m)
        #expect(row.openIssues == 1)
        s.showIssues(of: row.section.id)
        #expect(m.rows.count == 1)
        #expect(m.issueRestriction == "Open issues about \(row.section.title)")
        let counted = s.openIssueIDs(of: row.section.id)
        #expect(Set(ids(m)) == counted)
        s.clearIssueFilter()
        #expect(m.issueRestriction == nil)
        #expect(ids(m) == all)
        #expect(all.count > 1)
    }

    @Test func issueRestrictionSurvivesASortChange() async throws {
        let (s, m, row) = try await restricted()
        s.showIssues(of: row.section.id)
        m.state.sort = [SortKey(field: "severity", ascending: false)]
        #expect(m.rows.count == 1)
        m.toggleFilter(field: ListModel.statusField, value: "resolved")
        #expect(m.rows.isEmpty)
    }

    @Test func pickingTheIssuesSectionInTheSidebarShowsAllIssues() async throws {
        let (s, m, row) = try await restricted()
        s.showIssues(of: row.section.id)
        #expect(s.selectedSection == m.sectionID)
        s.select(section: row.section.id)
        s.select(section: m.sectionID)
        #expect(m.issueRestriction == nil)
        #expect(m.rows.count > 1)
    }

    @Test func otherSectionsIgnoreTheRestriction() async throws {
        let (s, _, row) = try await restricted()
        let other = ListModel(session: s, section: row.section)
        s.showIssues(of: row.section.id)
        #expect(other.issueRestriction == nil)
    }

    @Test func agreedOnlyNeverHidesIssues() async throws {
        let (s, m, row) = try await restricted()
        let all = ids(m)
        s.agreedOnly = true
        #expect(ids(m) == all)
        s.showIssues(of: row.section.id)
        #expect(m.rows.count == row.openIssues)
        let content = try #require(s.metamodel.sections.first { $0.folders.contains(requirements) })
        #expect(ListModel(session: s, section: content).rows.allSatisfy { $0.status == "accepted" })
    }

    @Test func sidebarCountsAndListsAgreeUnderAgreedOnly() async throws {
        for fixture in ["basic", "search", "arc42"] {
            let s = try await session(fixture)
            for agreedOnly in [false, true] {
                s.agreedOnly = agreedOnly
                for row in s.sidebar.flatMap(\.rows) {
                    #expect(ListModel(session: s, section: row.section).rows.count == row.count, "\(fixture) \(row.section.id) \(agreedOnly)")
                }
            }
        }
    }

    @Test func theIssueRestrictionIsPartOfTheHistory() async throws {
        let (s, m, row) = try await restricted()
        s.select(section: row.section.id)
        s.showIssues(of: row.section.id)
        #expect(s.issueFilter == row.section.id)
        s.select(page: PageRef(folder: "issues", stem: try #require(m.rows.first).ref.stem))
        #expect(s.issueFilter == row.section.id)
        s.back()
        #expect(s.issueFilter == row.section.id)
        s.back()
        #expect(s.issueFilter == nil)
        #expect(s.selectedSection == row.section.id)
        s.forward()
        #expect(s.issueFilter == row.section.id)
        // Leave and come back: restricted again.
        s.select(section: row.section.id)
        #expect(s.issueFilter == nil)
        s.back()
        #expect(s.issueFilter == row.section.id)
        #expect(m.rows.count == 1)
        // "Show all" records a place without it.
        s.clearIssueFilter()
        #expect(m.rows.count > 1)
        s.back()
        #expect(s.issueFilter == row.section.id)
        s.forward()
        #expect(s.issueFilter == nil)
    }

    @Test func stateSurvivesEncoding() async throws {
        let (s, m) = try await model("basic", folder: requirements)
        m.state.sort = [SortKey(field: "release", ascending: false), SortKey(field: "priority", ascending: true)]
        m.state.filters = ["priority": ["Must"], ListModel.statusField: ["accepted", "draft"]]
        let text = ListStates.encode([m.sectionID: m.state])
        let back = try #require(ListStates.decode(text)[m.sectionID])
        #expect(back == m.state)
        let section = try #require(s.metamodel.sections.first { $0.id == m.sectionID })
        let again = ListModel(session: s, section: section, state: back)
        #expect(ids(again) == ids(m))
    }

    @Test func brokenStoredTextGivesNoStates() {
        #expect(ListStates.decode("").isEmpty)
        #expect(ListStates.decode("{nope").isEmpty)
    }

    @Test func staleStateIsIgnored() async throws {
        let stale = ListState(sort: [SortKey(field: "gone", ascending: false)], filters: ["gone": ["x"]], mode: "gone")
        let (_, m) = try await model("basic", folder: requirements, state: stale)
        #expect(m.state.sort == m.presets[0].keys)
        #expect(m.state.filters.isEmpty)
        #expect(m.state.mode == ListModel.listMode)
        #expect(ids(m) == ["FR-001", "FR-002", "FR-003", "FR-005", "FR-004", "FR-006"])
    }

    @Test func noPresetNoCrash() async throws {
        let s = try await session("basic")
        let section = try #require(s.metamodel.sections.first { section in
            section.types.allSatisfy { s.metamodel.sortPresets(for: $0).isEmpty } && !section.folders.isEmpty
                && section.folders.contains { !s.store.pages(in: $0).isEmpty }
        })
        let m = ListModel(session: s, section: section)
        #expect(m.presets.isEmpty)
        #expect(m.state.sort.isEmpty)
        let found = ids(m)
        #expect(!found.isEmpty)
        #expect(found == found.sorted { $0.compare($1, options: .numeric) == .orderedAscending })
    }

    @Test func modesHoldOnlyTheListForNow() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        #expect(m.modes == [ListModel.listMode])
    }

    @Test func selectingARowGoesThroughHistory() async throws {
        let (s, m) = try await model("basic", folder: requirements)
        s.select(section: m.sectionID)
        let first = try #require(m.rows.first), second = m.rows[1]
        s.select(page: first.ref)
        s.select(page: second.ref)
        #expect(s.selectedPage == second.ref)
        #expect(s.selectedSection == m.sectionID)
        s.back()
        #expect(s.selectedPage == first.ref)
        s.select(page: PageRef(folder: requirements, stem: "nope"))
        #expect(s.selectedPage == first.ref)
    }

    @Test func badgesShowStatusAndPresetFields() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        let first = try #require(m.rows.first)
        #expect(m.badges(of: first) == ["accepted", "Must", "v1", "1"])
    }

    @Test func fieldLabelsAreGenericallyPrettified() {
        #expect(FieldLabel.text("raised-by") == "Raised by")
        #expect(FieldLabel.text("priority") == "Priority")
        #expect(FieldLabel.text("story_map") == "Story map")
    }

    @Test func togglingEditsTheState() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        m.toggleFilter(field: "priority", value: "Must")
        #expect(m.state.filters["priority"] == ["Must"])
        m.toggleFilter(field: "priority", value: "Must")
        #expect(m.state.filters["priority"] == nil)
        m.addSortKey("lane")
        #expect(m.state.sort.last == SortKey(field: "lane", ascending: true))
        m.addSortKey("lane")
        #expect(m.state.sort.filter { $0.field == "lane" }.count == 1)
        m.toggleDirection(at: 0)
        #expect(m.state.sort[0].ascending == false)
        m.removeSortKey(at: 0)
        #expect(m.state.sort.first?.field == "release")
        m.apply(preset: m.presets[0])
        #expect(m.state.sort == m.presets[0].keys)
    }

    @Test func missingValuesSortLastInBothDirections() async throws {
        let pages = [
            fake("FR-1", ["priority": "Must", "lane": "backbone"]),
            fake("FR-2", ["priority": "Must"]),
            fake("FR-3", ["priority": "Must", "lane": "display"]),
        ]
        let order = PageOrder(enums: ["lane": ["backbone", "platform", "display"]], statuses: nil)
        let up = order.arrange(pages, sort: [SortKey(field: "lane", ascending: true)], filters: [:], agreedOnly: false)
        let down = order.arrange(pages, sort: [SortKey(field: "lane", ascending: false)], filters: [:], agreedOnly: false)
        #expect(up.map(\.id) == ["FR-1", "FR-3", "FR-2"])
        #expect(down.map(\.id) == ["FR-3", "FR-1", "FR-2"])
    }

    @Test func undeclaredEnumValuesSortAfterDeclaredOnes() {
        let pages = [fake("A-1", ["lane": "zzz"]), fake("A-2", ["lane": "aaa"]), fake("A-3", ["lane": "display"])]
        let order = PageOrder(enums: ["lane": ["backbone", "platform", "display"]], statuses: nil)
        let up = order.arrange(pages, sort: [SortKey(field: "lane")], filters: [:], agreedOnly: false)
        #expect(up.map(\.id) == ["A-3", "A-2", "A-1"])
    }

    @Test func tiesEndInNumericIdOrder() {
        let pages = ["FR-10", "FR-2", "FR-1"].map { fake($0, [:]) }
        let order = PageOrder(enums: [:], statuses: nil)
        #expect(order.arrange(pages, sort: [], filters: [:], agreedOnly: false).map(\.id) == ["FR-1", "FR-2", "FR-10"])
        #expect(order.arrange(pages, sort: [SortKey(field: "lane", ascending: false)], filters: [:], agreedOnly: false).map(\.id) == ["FR-1", "FR-2", "FR-10"])
    }

    @Test func undeclaredEnumValuesStayAfterDeclaredOnesWhenDescending() {
        let pages = [fake("A-1", ["lane": "zzz"]), fake("A-2", ["lane": "backbone"]), fake("A-3", ["lane": "display"]), fake("A-4", [:])]
        let order = PageOrder(enums: ["lane": ["backbone", "platform", "display"]], statuses: nil)
        let down = order.arrange(pages, sort: [SortKey(field: "lane", ascending: false)], filters: [:], agreedOnly: false)
        #expect(down.map(\.id) == ["A-3", "A-2", "A-1", "A-4"])
    }

    @Test func textSortIgnoresDiacriticsAndCase() {
        let pages = [fake("A-1", ["role": "Zebra"]), fake("A-2", ["role": "Ärztin"]), fake("A-3", ["role": "arzt"]), fake("A-4", ["role": "Arzu"])]
        let order = PageOrder(enums: [:], statuses: nil)
        let up = order.arrange(pages, sort: [SortKey(field: "role")], filters: [:], agreedOnly: false)
        #expect(up.map(\.id) == ["A-3", "A-2", "A-4", "A-1"])
    }

    @Test func oneBrokenEntryKeepsTheOthers() {
        let good = ListState(sort: [SortKey(field: "x")], mode: "list")
        let text = #"{"A": {"sort": 5}, "B": \#(String(data: try! JSONEncoder().encode(good), encoding: .utf8)!), "C": "nope"}"#
        #expect(ListStates.decode(text) == ["B": good])
        let written = ListStates.updating(text, section: "D", with: good)
        #expect(Set(ListStates.decode(written).keys) == ["B", "D"])
        let fresh = ListStates.updating("{not json", section: "D", with: good)
        #expect(ListStates.decode(fresh) == ["D": good])
    }

    @Test func columnsStartWithTheUniversalFieldsOfTheMetamodel() async throws {
        let (s, m) = try await model("basic", folder: requirements)
        let universal = s.metamodel.universalFields
        #expect(universal.starts(with: ["id", "type", "title", "status"]))
        #expect(Array(m.columns.prefix(universal.count)) == universal)
        #expect(m.columns.contains("priority"))
    }

    @Test func sortPickerOffersOnlyUnusedColumns() async throws {
        let (_, m) = try await model("basic", folder: requirements)
        let used = m.state.sort.map(\.field)
        #expect(m.unusedColumns.allSatisfy { !used.contains($0) })
        #expect(m.unusedColumns.count == m.columns.count - used.count)
        let before = m.state.sort
        m.replaceSortKey(at: 0, with: used[1])
        m.addSortKey(used[2])
        #expect(m.state.sort == before)
    }

    @Test func aReplacedWikiReachesAnExistingModel() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let section = try #require(s.metamodel.sections.first { $0.folders.contains(requirements) })
        let m = ListModel(session: s, section: section)
        #expect(m.rows.count == 6)
        let file = copy.appending(path: "wiki/functional-requirements/FR-006-catalog-maintenance.md")
        try FileManager.default.removeItem(at: file)
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        #expect(m.rows.count == 5)
        #expect(!ids(m).contains("FR-006"))
    }

    @Test func largeListIsQuick() {
        let priorities = ["Must", "Should", "Could", "Won't"]
        let pages = (1...5000).map { n in
            fake("FR-\(n)", ["priority": priorities[n % 4], "release": "v\(n % 7)", "order": "\(n % 50)"], status: n % 3 == 0 ? "draft" : "accepted")
        }
        let order = PageOrder(enums: ["priority": priorities], statuses: ["draft", "review", "accepted"])
        let clock = ContinuousClock()
        var result: [Page] = []
        let time = clock.measure {
            result = order.arrange(
                pages,
                sort: [SortKey(field: "priority"), SortKey(field: "release"), SortKey(field: "order", ascending: false)],
                filters: ["status": ["accepted"]],
                agreedOnly: false
            )
        }
        #expect(result.count == 3334)
        // Measured 70 ms in a debug build. The limit leaves a factor of 5 for a loaded CI machine.
        #expect(time < .milliseconds(400), "took \(time)")
    }
}

private func fake(_ id: String, _ fields: [String: String], status: String = "draft") -> Page {
    let lines = (["id": id, "title": "Title \(id)", "status": status].merging(fields) { $1 })
        .map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
    return Page(ref: PageRef(folder: "f", stem: id), text: "---\n\(lines)\n---\nbody\n")
}
