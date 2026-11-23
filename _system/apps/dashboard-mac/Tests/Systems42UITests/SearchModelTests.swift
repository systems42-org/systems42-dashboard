import Foundation
import SwiftUI
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

/// Lets a test hold a backend call until it says go, so "an older result is dropped" needs no sleeping.
private actor SearchGate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        if open { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        open = true
        for w in waiting { w.resume() }
        waiting = []
    }
}

/// The model holds its session weakly, so a test keeps the sessions it opened alive here.
@MainActor private var openSessions: [WikiSession] = []

@MainActor
private func opened(_ fixture: String = "search") async throws -> (WikiSession, SearchModel) {
    let s = await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
    openSessions.append(s)
    let m = SearchModel(session: s)
    await m.settle()
    return (s, m)
}

private func coreIndex() throws -> SearchIndex {
    let store = WikiStore(root: try Preflight.open(Fixture.url("search")))
    return SearchIndex(store: store, metamodel: store.metamodel)
}

@MainActor @Suite struct SearchModelTests {
    private func found(_ m: SearchModel, _ query: String) async -> SearchModel {
        m.query = query
        m.commit()
        await m.settle()
        return m
    }

    // MARK: typing

    @Test func suggestionsWhileTyping() async throws {
        let (_, m) = try await opened()
        m.query = "keyhol"
        await m.settle()
        #expect(m.quick.first?.id == "STK-023")
        #expect(m.quick.allSatisfy { $0.passage == nil && $0.group == .hit })
        #expect(m.hits.isEmpty)
    }

    @Test func quickHasAtMostEight() async throws {
        let (_, m) = try await opened()
        m.query = "the"
        await m.settle()
        let all = search("the", in: try coreIndex(), withRelated: false)
        #expect(all.count > 8)
        #expect(m.quick.map(\.id) == all.prefix(8).map(\.id))
    }

    @Test func emptyQueryShowsNothing() async throws {
        let (_, m) = try await opened()
        for q in ["", "   ", "\n"] {
            _ = await found(m, q)
            #expect(m.quick.isEmpty && m.hits.isEmpty && m.related.isEmpty)
        }
        #expect(m.session?.shownSearch == nil)
    }

    @Test func onlyFillerWordsStillFinds() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "the a")
        let core = search("the a", in: try coreIndex(), withPassages: true).filter { $0.group == .hit }
        #expect(!m.quick.isEmpty)
        #expect(m.hits.map(\.id) == core.map(\.id))
    }

    @Test func filterSyntaxIsPlainText() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "status:draft")
        let core = search("status draft", in: try coreIndex(), withPassages: true).filter { $0.group == .hit }
        #expect(m.hits.map(\.id) == core.map(\.id))
        #expect(m.filter == SearchFilter())
    }

    @Test func hostileQueriesAreJustWords() async throws {
        let (_, m) = try await opened()
        for q in ["(.*)[", "\\", "a\u{0}b", String(repeating: "x", count: 5000), "<script>", "💥 ", "status:"] {
            _ = await found(m, q)
            #expect(m.quick.count <= 8)
        }
    }

    // MARK: full list

    @Test func commitShowsEverything() async throws {
        let (s, m) = try await opened()
        _ = await found(m, "keyholder")
        let core = search("keyholder", in: try coreIndex(), withPassages: true)
        #expect(m.hits.map(\.id) == core.filter { $0.group == .hit }.map(\.id))
        #expect(m.hits.allSatisfy { $0.passage != nil })
        #expect(m.hits.compactMap(\.passage) == core.filter { $0.group == .hit }.compactMap(\.passage))
        #expect(s.shownSearch == SearchRequest(query: "keyholder", filter: SearchFilter()))
    }

    @Test func reasonOnNonExactHits() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "keyholdr")
        #expect(m.hits.first { $0.id == "STK-023" }?.note == "typo: keyholdr → Keyholder")
        _ = await found(m, "keyholder")
        let exact = try #require(m.hits.first { $0.id == "STK-023" })
        #expect(exact.note == nil)
    }

    @Test func relatedGroupIsSeparate() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "keyholder")
        #expect(!m.related.isEmpty && m.related.count <= 5)
        #expect(Set(m.related.map(\.id)).isDisjoint(with: m.hits.map(\.id)))
        #expect(m.related.allSatisfy { $0.group == .related && $0.note == "linked from STK-023" })
        m.query = "keyholder"
        #expect(m.quick.allSatisfy { $0.group == .hit })
    }

    // MARK: filters

    @Test func statusFilterLeavesOnlyThatStatus() async throws {
        let (_, m) = try await opened()
        let everything = Set(await found(m, "the").hits.map(\.id))
        m.filter = SearchFilter(statuses: ["accepted"])
        await m.settle()
        #expect(!m.hits.isEmpty && m.hits.allSatisfy { $0.status == "accepted" })
        #expect(everything.isStrictSuperset(of: m.hits.map(\.id)))
    }

    @Test func priorityAndTagFilters() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "the")
        m.filter = SearchFilter(priorities: ["must"])
        await m.settle()
        #expect(m.hits.map(\.id).sorted() == ["FR-001", "FR-002"])
        _ = await found(m, "every")
        m.filter = SearchFilter(tags: ["navigation"])
        await m.settle()
        #expect(m.hits.map(\.id) == ["FR-004"])
        m.filter = SearchFilter(statuses: ["accepted"], tags: ["navigation"])
        await m.settle()
        #expect(m.hits.isEmpty)
    }

    @Test func filterIsKeptWhenOneCommitsAgain() async throws {
        let (_, m) = try await opened()
        m.filter = SearchFilter(statuses: ["accepted"])
        _ = await found(m, "the")
        #expect(m.hits.allSatisfy { $0.status == "accepted" })
    }

    /// Counts for the query "the", worked out by hand from `Tests/Golden/search/queries.json` (its 11 hits)
    /// and the frontmatter of the fixture pages.
    private static let theCounts: [String: [(String, Int)]] = [
        "type": [("Functional requirement", 5), ("Stakeholder", 4), ("Issue", 2)],
        "status": [("draft", 6), ("accepted", 3), ("open", 2)],
        "priority": [("should", 3), ("must", 2)],
        "tag": [("functional-requirement", 5), ("stakeholder", 4), ("issue", 2)],
    ]

    private func counts(_ m: SearchModel, _ field: String) throws -> [String: Int] {
        Dictionary(try #require(m.facets.first { $0.field == field }).values, uniquingKeysWith: { a, _ in a })
    }

    @Test func facetCountsMatch() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "the")
        #expect(m.hits.count == 11)
        #expect(m.facets.map(\.field) == SearchFilterFields.all.map(\.name))
        for (field, expected) in Self.theCounts {
            let values = try #require(m.facets.first { $0.field == field }).values
            #expect(values.map(\.0) == expected.map(\.0), "\(field) order")
            #expect(values.map(\.1) == expected.map(\.1), "\(field) counts")
        }
    }

    @Test func aFieldKeepsItsCountsWhileItIsFiltered() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "the")
        let all = try counts(m, "type")
        m.toggle(field: "type", value: "stakeholder")
        await m.settle()
        #expect(m.hits.count == 4)
        #expect(try counts(m, "type") == all)                                      // the other types keep their counts
        #expect(try counts(m, "status") == ["accepted": 2, "draft": 2])            // the other fields follow the hits
        m.toggle(field: "type", value: "issue")                                    // a second value of the same field adds its hits
        await m.settle()
        #expect(m.hits.count == 6)
        #expect(try counts(m, "type") == all)
        #expect(try counts(m, "status") == ["accepted": 2, "draft": 2, "open": 2])
        // another field narrows this one: status draft leaves 6 hits, the type counts follow it
        m.clearFilter()
        m.toggle(field: "status", value: "draft")
        await m.settle()
        #expect(try counts(m, "type") == ["Functional requirement": 4, "Stakeholder": 2])
        #expect(try counts(m, "status") == ["draft": 6, "accepted": 3, "open": 2])
    }
    @Test func optionsCarryTheWikisLabelsAndCounts() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "the")
        let priorities = m.options(for: "priority")
        #expect(priorities.prefix(3).map(\.value) == ["must", "should", "could"])
        #expect(priorities.first?.label == "Must")
        let types = m.options(for: "type")
        #expect(types.contains { $0.label == "Stakeholder" })
        #expect(m.options(for: "nonsense").isEmpty)
    }

    @Test func toggleFilterChangesTheListAndTheHistoryPlace() async throws {
        let (s, m) = try await opened()
        _ = await found(m, "the")
        let count = s.historyCount
        m.toggle(field: "status", value: "accepted")
        await m.settle()
        #expect(m.filter.statuses == ["accepted"])
        #expect(m.hits.allSatisfy { $0.status == "accepted" })
        #expect(s.shownSearch?.filter.statuses == ["accepted"])
        #expect(s.historyCount == count)
        m.toggle(field: "status", value: "accepted")
        #expect(m.filter == SearchFilter())
        m.clearFilter()
        #expect(m.filter == SearchFilter())
    }

    // MARK: selection and history

    @Test func selectingAHitOpensThePage() async throws {
        let (s, m) = try await opened()
        m.query = "keyholder"
        await m.settle()
        let hit = try #require(m.quick.first)
        m.open(hit)
        #expect(s.selectedPage == hit.ref)
        #expect(s.selectedSection != nil)
        #expect(s.shownSearch == nil)
        #expect(!m.suggestionsOpen)
    }

    @Test func aHitOfTheListKeepsTheListAndBackReturnsToIt() async throws {
        let (s, m) = try await opened()
        _ = await found(m, "keyholder")
        let hit = try #require(m.hits.first)
        m.open(hit, keepingResults: true)
        #expect(s.selectedPage == hit.ref)
        #expect(s.shownSearch?.query == "keyholder")
        s.back()
        #expect(s.shownSearch?.query == "keyholder")
        #expect(s.selectedPage == nil)
        m.followSession()
        await m.settle()
        #expect(m.hits.first?.id == hit.id)
        s.forward()
        #expect(s.selectedPage == hit.ref)
    }

    @Test func backLeavesTheResultsAndTheModelFollows() async throws {
        let (s, m) = try await opened()
        let section = try #require(s.metamodel.sections.first?.id)
        s.select(section: section)
        _ = await found(m, "keyholder")
        #expect(s.shownSearch != nil)
        s.back()
        #expect(s.shownSearch == nil)
        m.followSession()
        #expect(m.hits.isEmpty)
        s.forward()
        m.followSession()
        await m.settle()
        #expect(!m.hits.isEmpty)
        #expect(m.query == "keyholder")
    }

    @Test func choosingASectionClosesTheResults() async throws {
        let (s, m) = try await opened()
        _ = await found(m, "keyholder")
        let section = try #require(s.metamodel.sections.first?.id)
        s.select(section: section)
        #expect(s.shownSearch == nil)
        m.followSession()
        #expect(m.hits.isEmpty)
    }

    @Test func followingTheSessionDoesNotOpenTheSuggestions() async throws {
        let (s, m) = try await opened()
        _ = await found(m, "keyholder")
        s.select(section: try #require(s.metamodel.sections.first?.id))
        s.back()
        m.followSession()
        #expect(!m.suggestionsOpen)
    }

    // MARK: keyboard

    @Test func arrowKeysMoveThroughTheSuggestions() async throws {
        let (s, m) = try await opened()
        m.query = "the"
        await m.settle()
        #expect(m.suggestionsOpen && m.highlighted == nil)
        m.moveHighlight(by: -1)
        #expect(m.highlighted == m.quick.count - 1)
        m.moveHighlight(by: 1)
        #expect(m.highlighted == 0)
        m.moveHighlight(by: 1)
        #expect(m.highlighted == 1)
        m.submit()
        #expect(s.selectedPage == m.quick[1].ref)
        #expect(!m.suggestionsOpen)
    }

    @Test func returnWithoutAHighlightShowsTheList() async throws {
        let (s, m) = try await opened()
        m.query = "keyholder"
        await m.settle()
        m.submit()
        await m.settle()
        #expect(s.shownSearch?.query == "keyholder")
        #expect(!m.hits.isEmpty)
        #expect(!m.suggestionsOpen)
    }

    @Test func escapeClosesTheSuggestionsAndTypingOpensThemAgain() async throws {
        let (_, m) = try await opened()
        m.query = "key"
        await m.settle()
        #expect(m.suggestionsOpen)
        m.dismissSuggestions()
        #expect(!m.suggestionsOpen && m.highlighted == nil)
        m.query = "keyh"
        #expect(m.suggestionsOpen)
        m.query = ""
        #expect(!m.suggestionsOpen)
    }

    @Test func focusRequestCounts() async throws {
        let (_, m) = try await opened()
        let before = m.focusRequests
        m.focusField()
        #expect(m.focusRequests == before + 1)
    }

    @Test func downArrowWithoutSuggestionsIsPassedOn() async throws {
        let (_, m) = try await opened()
        #expect(m.moveHighlight(by: 1) == false)           // nothing typed
        m.query = "the"
        await m.settle()
        #expect(m.moveHighlight(by: 1) == true)
        m.dismissSuggestions()
        #expect(m.moveHighlight(by: 1) == false && m.highlighted == nil)
    }

    @Test func returnMovesTheFocusToTheList() async throws {
        let (_, m) = try await opened()
        let before = m.listFocusRequests
        m.query = "keyholder"
        m.submit()
        #expect(m.listFocusRequests == before + 1)
        m.query = ""
        m.commit()                                          // nothing to show, no focus move
        #expect(m.listFocusRequests == before + 1)
    }

    // MARK: pages with the same id, tours and reloads

    @Test func twoPagesWithOneIdAreTwoResults() async throws {
        let copy = try Fixture.tempCopy("search")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        for (stem, status) in [("STK-900-twin-a", "draft"), ("STK-900-twin-b", "accepted")] {
            let text = "---\nid: STK-900\ntype: stakeholder\ntitle: Twinword\nstatus: \(status)\ntags: [stakeholder, twin]\n---\n\n# Twinword\n\nSame id.\n"
            try text.write(to: copy.appending(path: "wiki/stakeholders/\(stem).md"), atomically: true, encoding: .utf8)
        }
        let s = await WikiSession.open(try Preflight.open(copy))
        openSessions.append(s)
        let m = SearchModel(session: s)
        _ = await found(m, "twinword")
        #expect(m.hits.count == 2 && Set(m.hits.compactMap(\.ref)).count == 2)
        m.query = "twinword"
        await m.settle()
        #expect(m.quick.count == 2 && Set(m.quick.compactMap(\.ref)).count == 2)
        #expect(try counts(m, "status") == ["draft": 1, "accepted": 1])
        #expect(try counts(m, "tag") == ["stakeholder": 2, "twin": 2])
        #expect(try counts(m, "type") == ["Stakeholder": 2])
    }

    @Test func aTourStartedWhileResultsShowClosesThem() async throws {
        let (s, m) = try await opened()
        _ = await found(m, "keyholder")
        #expect(s.shownSearch != nil)
        let history = s.historyCount
        s.tour.start()
        try #require(s.tour.isActive)
        #expect(s.shownSearch == nil)
        #expect(s.historyCount == history)
        m.followSession()
        #expect(m.hits.isEmpty)
        s.tour.stop()
        s.back()                                            // the history is as before the tour
        #expect(s.historyCount == history)
    }

    @Test func aReloadThatRemovesTheOpenedPage() async throws {
        let copy = try Fixture.tempCopy("search")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        openSessions.append(s)
        let m = SearchModel(session: s)
        _ = await found(m, "keyholder")
        let hit = try #require(m.hits.first { $0.id == "STK-023" })
        let ref = try #require(hit.ref)
        m.open(hit, keepingResults: true)
        await m.settle()
        #expect(m.pageMarks(for: ref).matches("keyholder"))
        try FileManager.default.removeItem(at: copy.appending(path: "wiki/stakeholders/STK-023-keyholder.md"))
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        m.followWiki()
        #expect(m.pageMarks(for: ref).isEmpty)
        await m.settle()
        #expect(!m.hits.contains { $0.id == "STK-023" })
        #expect(m.related.allSatisfy { $0.id != "STK-023" })
        #expect(s.shownSearch?.query == "keyholder")
        #expect(m.pageMarks(for: ref).isEmpty)
    }

    // MARK: reasons for the screen reader

    @Test func rowLabelNamesTheReasonAfterTheTitle() async throws {
        let (_, m) = try await opened()
        _ = await found(m, "keyholdr")
        let hit = try #require(m.hits.first { $0.id == "STK-023" })
        #expect(SearchRows.spoken(hit) == "Keyholder, STK-023. typo: keyholdr → Keyholder")
        _ = await found(m, "keyholder")
        let exact = try #require(m.hits.first { $0.id == "STK-023" })
        #expect(SearchRows.spoken(exact) == "Keyholder, STK-023")
    }

    // MARK: marks in the shown page

    @Test func pageMarksFollowTheOpenedPage() async throws {
        let (s, m) = try await opened()
        let keyholder = PageRef(folder: "stakeholders", stem: "STK-023-keyholder")
        #expect(m.pageMarks(for: keyholder).isEmpty)
        _ = await found(m, "facilitator")
        let hit = try #require(m.hits.first { $0.id == "STK-023" })
        let ref = try #require(hit.ref)
        m.open(hit, keepingResults: true)
        #expect(m.pageMarks(for: ref).isEmpty)          // unmarked until the marks arrive
        await m.settle()
        #expect(m.pageMarks(for: ref).matches("Facilitator"))
        #expect(m.pageMarks(for: PageRef(folder: "stakeholders", stem: "other")).isEmpty)
        s.select(section: try #require(s.metamodel.sections.first?.id))
        #expect(m.pageMarks(for: ref).isEmpty)
    }

    @Test func aPageOpenedFromASuggestionIsMarkedToo() async throws {
        let (s, m) = try await opened()
        m.query = "facilitator"
        await m.settle()
        let hit = try #require(m.quick.first { $0.id == "STK-023" })
        m.open(hit)
        #expect(s.shownSearch == nil)
        await m.settle()
        #expect(m.pageMarks(for: try #require(hit.ref)).matches("facilitator"))
    }

    @Test func aMarkResultOfAnOlderPageIsDropped() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
        openSessions.append(s)
        let held = SearchGate()
        var backend = SearchBackend.live
        let live = backend.mark
        backend.mark = { text, query, passage in
            if query == "facilitator" { await held.pass() }
            return await live(text, query, passage)
        }
        let m = SearchModel(session: s, backend: backend)
        await m.settle()
        m.query = "facilitator"
        await m.settle()
        let first = try #require(m.quick.first { $0.id == "STK-023" })
        m.open(first)                                   // marks held
        let before = m.arrivals
        m.query = "navigation"
        await m.finished(atLeast: before + 1)           // not settle(): the held marks would block it
        let second = try #require(m.quick.first { $0.id == "DT-002" })
        m.open(second)
        await m.finished(atLeast: before + 2)
        await held.release()
        await m.finished(atLeast: before + 3)
        #expect(m.pageMarks(for: try #require(first.ref)).isEmpty)
        #expect(m.pageMarks(for: try #require(second.ref)).matches("navigation"))
    }

    @Test func aFiveMegabytePageIsMarkedOffTheMainThread() async throws {
        let line = "The keyholder opens the workshop board and the facilitator checks navigation tips. "
        let text = String(repeating: line, count: 5_000_000 / line.count)
        #expect(text.utf8.count >= 4_900_000)
        let query = "keyholder workshop board facilitator navigation tips opens checks alpha beta"
        let clock = ContinuousClock()
        let time = await clock.measure {
            let marks = await SearchBackend.live.mark(text, query, [])
            #expect(marks.matches("Keyholder") && marks.matches("tips") && !marks.matches("the"))
        }
        #expect(time < .seconds(30), "took \(time)")
    }
    @Test func markedWordsMatchTypedFormsAndSkipFillers() {
        let text = "What the Keyholder does. Keyholders start the workshop."
        let marks = PageMarks.compute(text: text, query: "what keyholdr", matchedInPassage: ["Keyholder"])
        #expect(marks.words == ["keyholdr"])
        #expect(marks.matches("Keyholder") && marks.matches("keyholders"))
        #expect(!marks.matches("what") && !marks.matches("workshop"))
        let all = PageMarks.compute(text: text, query: "workshop", matchedInPassage: [])
        #expect(all.matches("Workshop"))
        #expect(PageMarks.compute(text: text, query: "", matchedInPassage: []).isEmpty)
    }

    @Test func marksUseTheRankersLimits() {
        #expect(SearchLimit.mostQueryWords == 16 && SearchLimit.longestQuery == 200)
        let many = (1...30).map { "word\($0)" }.joined(separator: " ")
        #expect(PageMarks.words(of: many).count == 16)
        #expect(PageMarks.words(of: many).last == "word16")
        // the 200 character cut: a word that starts after it is not a query word
        let cut = String(repeating: "a", count: 198) + " bb cc"
        #expect(PageMarks.words(of: cut) == ["b"])   // the long word is over the word cap, "bb" is cut after its first letter
        #expect(PageMarks.words(of: "xx " + String(repeating: "k", count: 65)) == ["xx"])   // over the word cap
        let marks = PageMarks.compute(text: String(repeating: "k", count: 65) + " xx", query: "xx", matchedInPassage: [])
        #expect(marks.matches("xx") && !marks.matches(String(repeating: "k", count: 65)))
    }
    @Test func markingSplitsTextAtWordEdges() {
        let marks = PageMarks.compute(text: "A key, the Keyholder; keys.", query: "key", matchedInPassage: [])
        let marked = marks.apply(to: AttributedString("A key, the Keyholder; keys."))
        let words = marked.runs.filter { $0.backgroundColor != nil }.map { String(marked[$0.range].characters) }
        #expect(words == ["key", "Keyholder", "keys"])
    }

    // MARK: threads and reloads

    @Test func untilTheIndexIsReadyNothingShowsAndTheModelSaysSo() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
        openSessions.append(s)
        let gate = SearchGate()
        var backend = SearchBackend.live
        backend.build = { store, metamodel in
            await gate.pass()
            return SearchIndex(store: store, metamodel: metamodel)
        }
        let m = SearchModel(session: s, backend: backend)
        #expect(m.isIndexing)
        m.query = "keyholder"
        m.commit()
        #expect(m.quick.isEmpty && m.hits.isEmpty)
        #expect(m.isIndexing)
        await gate.release()
        await m.settle()
        #expect(!m.isIndexing)
        #expect(m.quick.first?.id == "STK-023")
        #expect(!m.hits.isEmpty)
    }

    @Test func aResultOfAnOlderQueryIsDropped() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
        openSessions.append(s)
        let slow = SearchGate()
        var backend = SearchBackend.live
        let live = backend.run
        backend.run = { job in
            if job.query == "keyholder" { await slow.pass() }
            return await live(job)
        }
        let m = SearchModel(session: s, backend: backend)
        await m.settle()
        m.query = "keyholder"        // held
        m.query = "navigation"       // newer
        await m.settle()
        #expect(m.quick.first?.id == "DT-002")
        let before = m.arrivals
        await slow.release()
        await m.finished(atLeast: before + 1)   // the held run came back and was judged
        #expect(m.quick.first?.id == "DT-002")
    }

    @Test func aFullListOfAnOlderQueryIsDropped() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
        openSessions.append(s)
        let slow = SearchGate()
        var backend = SearchBackend.live
        let live = backend.run
        backend.run = { job in
            if job.full, job.query == "keyholder" { await slow.pass() }
            return await live(job)
        }
        let m = SearchModel(session: s, backend: backend)
        await m.settle()
        _ = await found(m, "navigation")
        m.query = "keyholder"
        m.commit()                    // held
        m.query = "navigation"
        m.commit()
        await m.settle()
        #expect(m.hits.first?.id == "DT-002")
        let before = m.arrivals
        await slow.release()
        await m.finished(atLeast: before + 1)
        #expect(m.hits.first?.id == "DT-002")
        #expect(m.facets.isEmpty == false && m.related.allSatisfy { $0.note != "linked from STK-023" })
    }

    @Test func aFullListOfAnOlderFilterIsDropped() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
        openSessions.append(s)
        let slow = SearchGate()
        var backend = SearchBackend.live
        let live = backend.run
        backend.run = { job in
            if job.full, job.filter.statuses == ["draft"] { await slow.pass() }
            return await live(job)
        }
        let m = SearchModel(session: s, backend: backend)
        await m.settle()
        _ = await found(m, "the")
        m.toggle(field: "status", value: "draft")       // held
        m.clearFilter()
        m.toggle(field: "status", value: "accepted")
        await m.settle()
        #expect(m.hits.count == 3 && m.hits.allSatisfy { $0.status == "accepted" })
        let before = m.arrivals
        await slow.release()
        await m.finished(atLeast: before + 1)
        #expect(m.hits.count == 3 && m.hits.allSatisfy { $0.status == "accepted" })
        #expect(s.shownSearch?.filter.statuses == ["accepted"])
    }

    @Test func supersededWorkIsCancelled() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
        openSessions.append(s)
        let cancelled = SearchCounter()
        let started = SearchGate()
        var backend = SearchBackend.live
        backend.run = { job in
            guard job.query == "keyholder" else { return SearchOutcome() }
            await started.release()
            try? await Task.sleep(for: .seconds(60))     // returns at once when the task is cancelled
            if Task.isCancelled { _ = await cancelled.next() }
            return SearchOutcome()
        }
        let m = SearchModel(session: s, backend: backend)
        await m.settle()
        m.query = "keyholder"
        await started.pass()
        m.query = "navigation"
        await m.settle()
        while await cancelled.value == 0 { await Task.yield() }
        #expect(await cancelled.value == 1)
    }
    @Test func aResultOfAnOlderWikiIsDropped() async throws {
        let copy = try Fixture.tempCopy("search")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let old = copy.appending(path: "wiki/stakeholders/STK-099-old-name.md")
        func page(_ title: String) -> String {
            "---\nid: STK-099\ntype: stakeholder\ntitle: \(title)\nstatus: draft\ntags: [stakeholder]\n---\n\n# \(title)\n\nText.\n"
        }
        try page("Zeppelin pilot").write(to: old, atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        openSessions.append(s)
        let first = SearchGate()
        let calls = SearchCounter()
        var backend = SearchBackend.live
        backend.build = { store, metamodel in
            let number = await calls.next()
            if number == 1 { await first.pass() }
            return SearchIndex(store: store, metamodel: metamodel)
        }
        let m = SearchModel(session: s, backend: backend)       // build 1 on the old page, held
        try FileManager.default.removeItem(at: old)
        try page("Dirigible pilot").write(to: copy.appending(path: "wiki/stakeholders/STK-099-new-name.md"), atomically: true, encoding: .utf8)
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        m.followWiki()                                          // build 2 on the new page
        m.query = "dirigible"
        await m.settle()
        #expect(m.quick.first?.id == "STK-099")
        let before = m.arrivals
        await first.release()
        await m.finished(atLeast: before + 1)                   // build 1 came back and was judged
        #expect(m.quick.first?.id == "STK-099")
        m.query = "zeppelin"
        await m.settle()
        #expect(m.quick.isEmpty)                                // a stale index would still know the old title
        #expect(!m.isIndexing)
    }
    @Test func indexRebuildsAfterReload() async throws {
        let copy = try Fixture.tempCopy("search")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        openSessions.append(s)
        let m = SearchModel(session: s)
        _ = await found(m, "zeppelin")
        #expect(m.hits.isEmpty)
        let page = "---\nid: STK-099\ntype: stakeholder\ntitle: Zeppelin pilot\nstatus: draft\ntags: [stakeholder]\n---\n\n# Zeppelin pilot\n\nFlies.\n"
        try page.write(to: copy.appending(path: "wiki/stakeholders/STK-099-zeppelin-pilot.md"), atomically: true, encoding: .utf8)
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        m.followWiki()
        #expect(m.isIndexing)
        await m.settle()
        #expect(m.hits.first?.id == "STK-099")
        #expect(m.quick.first?.id == "STK-099")
    }

    @Test func theSessionOwnsTheModelAndTheModelDoesNotOwnTheSession() async throws {
        weak var weakSession: WikiSession?
        var model: SearchModel?
        do {
            let s = await WikiSession.open(try Preflight.open(Fixture.url("search")))
            weakSession = s
            model = s.search
            #expect(s.search === model)
        }
        #expect(weakSession == nil)
        #expect(model?.session == nil)
        model?.query = "key"
        model?.commit()
        #expect(model?.hits.isEmpty == true)
    }

    // MARK: size

    @Test func twoThousandPagesStayFluent() async throws {
        let copy = try Fixture.tempCopy("search")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"]
        for n in 1...2000 {
            let id = "STK-\(1000 + n)"
            let title = "\(words[n % 10]) \(words[(n / 10) % 10]) person \(n)"
            let body = (0..<8).map { "Sentence \($0) about \(words[($0 + n) % 10]) and \(words[($0 * 3 + n) % 10]) work." }.joined(separator: " ")
            let text = "---\nid: \(id)\ntype: stakeholder\ntitle: \(title)\nstatus: \(n % 2 == 0 ? "draft" : "accepted")\ntags: [stakeholder, \(words[n % 10])]\n---\n\n# \(title)\n\n\(body)\n"
            try text.write(to: copy.appending(path: "wiki/stakeholders/\(id)-p\(n).md"), atomically: true, encoding: .utf8)
        }
        let s = await WikiSession.open(try Preflight.open(copy))
        openSessions.append(s)
        let m = SearchModel(session: s)
        let clock = ContinuousClock()
        let time = await clock.measure {
            await m.settle()
            for q in ["a", "al", "alp", "alpha", "alpha brav", "alpha bravo", "keyholder"] {
                m.query = q
                await m.settle()
            }
            m.commit()
            await m.settle()
        }
        #expect(m.quick.count <= 8)
        #expect(time < .seconds(30), "took \(time)")
        #expect(m.hits.first?.id == "STK-023")
    }
}

private actor SearchCounter {
    private var n = 0
    func next() -> Int { n += 1; return n }
    var value: Int { n }
}
