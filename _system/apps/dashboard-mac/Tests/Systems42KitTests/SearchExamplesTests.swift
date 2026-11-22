import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport

/// Every test of `_system/apps/dashboard/tests/test_search_examples.py`, with the same values,
/// run on the fixture `search`. The test name is the Python name in camel case.
@Suite struct SearchExamplesTests {
    private func index() throws -> SearchIndex {
        let store = WikiStore(root: try Preflight.open(Fixture.url("search")))
        return SearchIndex(store: store, metamodel: store.metamodel)
    }

    private func hits(_ query: String, _ filter: SearchFilter = SearchFilter()) throws -> [SearchHit] {
        search(query, in: try index(), filter: filter, withPassages: false).filter { $0.group == .hit }
    }

    private func ids(_ query: String) throws -> [String] { try hits(query).map(\.id) }

    private func hit(_ query: String, _ id: String) throws -> SearchHit {
        try #require(try hits(query).first { $0.id == id }, "\(id) is no hit of \(query)")
    }

    private func passages(_ query: String) throws -> [String: Passage] {
        let found = search(query, in: try index(), filter: SearchFilter(), withPassages: true)
        return Dictionary(uniqueKeysWithValues: found.filter { $0.group == .hit }.compactMap { h in h.passage.map { (h.id, $0) } })
    }

    private func related(_ query: String) throws -> [SearchHit] {
        search(query, in: try index(), filter: SearchFilter(), withPassages: true).filter { $0.group == .related }
    }

    /// An index of hand-made pages, as the Python tests feed the ranker.
    private func ranked(_ entries: [SearchEntry], _ query: String, synonyms: [[String]] = []) -> [SearchHit] {
        search(query, in: SearchIndex(entries: entries, synonyms: synonyms), filter: SearchFilter(), withPassages: false)
    }

    private func entry(_ id: String, title: String, type: String = "Issue", aliases: [String] = [], plain: String = "",
                       fields: [String: [String]] = [:]) -> SearchEntry {
        SearchEntry(id: id, type: type, title: title, aliases: aliases, plain: plain, fields: fields)
    }

    // MARK: FR-002 typos and word forms

    @Test func keyholderExactFirst() throws {
        #expect(try ids("keyholder").first == "STK-023")
    }

    @Test func fr002TypoKeyholdr() throws {
        #expect(try ids("keyholdr").prefix(3).contains("STK-023"))
    }

    @Test func fr002TypoStakholdrs() throws {
        #expect(try ids("stakholdrs").prefix(3).contains { $0.hasPrefix("STK-") })
    }

    @Test func fr002WordFormRequirementEngineer() throws {
        #expect(try ids("requirement engineer").prefix(3).contains("STK-003"))
    }

    @Test func fr002IdPrefix() throws {
        #expect(try ids("STK-02").prefix(4).sorted() == ["STK-020", "STK-021", "STK-022", "STK-023"])
    }

    @Test func fr002ExactAboveTypo() throws {
        let found = try ids("test")
        let test = try #require(found.firstIndex(of: "FR-003"))
        let text = try #require(found.firstIndex(of: "FR-002"))
        #expect(test < text)
    }

    @Test func fr002MatchWordRules() {
        #expect(matchKind(query: "keyholder", word: "keyholder") == .exact)
        #expect(matchKind(query: "requirement", word: "requirements") == .prefix)
        #expect(matchKind(query: "search", word: "searched") == .prefix)
        #expect(matchKind(query: "engineers", word: "engineer") == .form)
        #expect(matchKind(query: "starts", word: "started") == .form)
        #expect(matchKind(query: "keyhol", word: "keyholder") == .prefix)
        #expect(matchKind(query: "keyholdr", word: "keyholder") == .typo)
        #expect(matchKind(query: "stakholdrs", word: "stakeholders") == .typo)
        #expect(matchKind(query: "tset", word: "test") == .typo)
        #expect(matchKind(query: "tst", word: "test") == nil)
        #expect(matchKind(query: "app", word: "apple") == .prefix)
        #expect(matchKind(query: "stk-02", word: "stk-023") == .prefix)
        #expect(matchKind(query: "stk-024", word: "stk-023") == nil)
        #expect(matchKind(query: "trainers", word: "trainer") == .form)
        #expect(matchKind(query: "trainer", word: "brainer") == .typo)
        #expect(matchKind(query: "trainer", word: "bxainer") == nil)
        #expect(matchKind(query: "ärztn", word: "ärztin") == .typo)
    }

    @Test func fr002Stem() {
        #expect(["started", "starts", "requirements", "boxes", "uses", "using", "is"].map(stem)
            == ["start", "start", "requirement", "box", "use", "using", "is"])
    }

    @Test func fr002ExactBeatsTypoInAnyPlace() throws {
        let found = try ids("test")
        let body = try #require(found.firstIndex(of: "FR-003"))
        let title = try #require(found.firstIndex(of: "FR-006"))
        #expect(body < title)   // body "test" above title "Text tools"
        let result = ranked([
            entry("A-1", title: "Mist"),
            entry("B-1", title: "Other", fields: ["priority": ["must"]]),
            entry("C-1", title: "Other", plain: "Musts and more"),
        ], "must")
        #expect(result.map(\.id) == ["B-1", "C-1", "A-1"])   // exact field, word form, typo title
        #expect(result[0].score > result[1].score && result[1].score > result[2].score)
    }

    @Test func fr002TypoTiePrefersSameFirstLetter() throws {
        let found = try ids("seach")
        let search = try #require(found.firstIndex(of: "FR-007"))
        let reach = try #require(found.firstIndex(of: "FR-009"))
        #expect(search < reach)   // "Search the wiki" above "Reach"
    }

    @Test func fr002StemTypoUsesTheStemLength() throws {
        #expect(!(try ids("searches")).contains("FR-009"))   // search to reach is 2 edits, 6 letters allow 1
    }

    @Test func fr002IdNumberAlone() throws {
        #expect(try ids("023").first == "STK-023")
    }

    @Test func fr002NonAsciiTypo() throws {
        #expect(try ids("ärztn").contains("STK-022"))   // Ärztin, one letter missing
    }

    // MARK: FR-003 aliases and glossary synonyms

    @Test func fr003Alias() throws {
        #expect(try ids("Jedi Master").prefix(3).contains("STK-023"))
    }

    @Test func fr003AliasBelowExactTitle() throws {
        let result = ranked([
            entry("STK-001", title: "Keyholder", type: "Stakeholder", aliases: ["Jedi Master"]),
            entry("STK-002", title: "Jedi Master", type: "Stakeholder"),
        ], "jedi master")
        #expect(result.map(\.id) == ["STK-002", "STK-001"])
        #expect(result[0].score > result[1].score)
        #expect(try hit("Jedi Master", "STK-023").score < 100)
    }

    @Test func fr003AliasBelowAPhraseInATitle() throws {
        let found = try ids("jedi master")
        let phrase = try #require(found.firstIndex(of: "ISS-002"))   // "Guide to the Jedi Master role"
        let alias = try #require(found.firstIndex(of: "STK-023"))
        #expect(phrase < alias)
        #expect(try hit("jedi master", "ISS-002").score > hit("jedi master", "STK-023").score)
    }

    @Test func fr003SynonymGroupWorksBothWays() throws {
        #expect(try ids("moderator").contains("DT-001"))   // the term's own alias
        #expect(try ids("moderator").contains("STK-023"))  // says "facilitator" in its body
        #expect(try ids("facilitator").contains("DT-001"))
    }

    @Test func fr003GlossaryAlias() throws {
        #expect(try ids("moderator").prefix(3).contains("FR-001"))   // FR-001 says only "facilitator"
    }

    // MARK: FR-004 question-style queries

    @Test func fr004Question() throws {
        #expect(try ids("who starts the app").prefix(3).contains("STK-023"))
    }

    @Test func fr004PartialBelowFull() throws {
        let found = try ids("keyholder workshop")
        #expect(found.first == "STK-023")   // the only page with both words
        for one in ["ISS-001", "STK-021", "FR-001"] {
            #expect(found.contains(one), "\(one)")
            #expect(try hit("keyholder workshop", one).note == "matches 1 of 2 words")
        }
    }

    @Test func fr004PartialAfterEveryFullHit() {
        let result = ranked([
            entry("A-1", title: "Keyholder"),
            entry("B-1", title: "Other", plain: "keyholder and workshop"),
            entry("C-1", title: "Workshop keys"),
        ], "keyholder workshop")
        #expect(result.first?.id == "B-1")   // both words, in the body only
        #expect(result.dropFirst().allSatisfy { $0.note == "matches 1 of 2 words" })
        let best = result.first?.score ?? 0
        #expect(result.dropFirst().allSatisfy { $0.score < best })   // the score agrees with the order
    }

    @Test func fr004FillerWordsDropped() throws {
        #expect(try ids("who starts the app").first == "STK-023")
        #expect(try hit("what is the keyholder", "STK-023").note == nil)
    }

    @Test func fr004FillerWordsStillCountForAnExactTitle() throws {
        let found = try hits("search the wiki")
        #expect(found.first?.id == "FR-007" && found.first?.score == 100)   // not tied with "Wiki search tips"
        #expect(try hit("search the wiki", "FR-008").score < 100)
    }

    @Test func fr004GlossaryTermWithAFillerWord() throws {
        #expect(try hit("definition of done", "FR-008").note == "via alias of Definition of Done")   // says only "DoD"
        #expect(try hit("dod", "DT-003").note == "via alias of Definition of Done")
    }

    @Test func fr004OnlyFillerWords() throws {
        #expect(!(try hits("the a")).isEmpty)   // a query of filler words alone still finds pages
    }

    // MARK: FR-005 reason for every non-exact hit

    @Test func fr005Notes() throws {
        #expect(try hit("keyholdr", "STK-023").note == "typo: keyholdr → Keyholder")
        #expect(try hit("who starts the app", "STK-023").note == "word form: starts → started")
        #expect(try hit("Jedi Master", "STK-023").note == "via alias of Keyholder")
        #expect(try hit("moderator", "FR-001").note == "via alias of Facilitator")
    }

    @Test func fr005NoNoteOnExactHits() throws {
        #expect(try hit("keyholder", "STK-023").note == nil)
        #expect(try hit("STK-02", "STK-020").note == nil)
        #expect(try hit("test", "FR-003").note == nil)
        #expect(try hit("search", "FR-006").note == nil)   // "searched" starts with the word as typed
        #expect(try hit("requirement engineer", "STK-003").note == nil)
    }

    // MARK: FR-006 tags and fields

    @Test func fr006PriorityMust() throws {
        let found = try ids("Must")
        #expect(found.contains("FR-001") && found.contains("FR-002"))
    }

    @Test func fr006TagBetweenTitleAndBody() throws {
        let found = try ids("navigation")
        let title = try #require(found.firstIndex(of: "DT-002"))
        let tag = try #require(found.firstIndex(of: "FR-004"))
        let body = try #require(found.firstIndex(of: "FR-005"))
        #expect(title < tag && tag < body)
    }

    // MARK: FR-007 highlighted passage

    @Test func fr007BodyHitShowsMarkedSentence() throws {
        let found = try passages("facilitator")
        let keyholder = try #require(found["STK-023"])
        #expect(keyholder.text == "Works with the facilitator in every workshop.")
        #expect(keyholder.marked == ["facilitator"])
        #expect(try #require(found["FR-001"]).marked.contains("facilitator"))
        for query in ["person", "start", "session"] {   // body-only queries: every hit is marked
            for (id, passage) in try passages(query) {
                #expect(!passage.marks.isEmpty, "\(query) \(id)")
            }
        }
    }

    @Test func fr007TitleHitShowsFirstSentence() throws {
        let found = try passages("facilitator")
        #expect(found["DT-001"]?.text == "Person who guides a session.")
        #expect(found["DT-001"]?.marks == [])
    }

    @Test func fr007TitleHitSkipsHeadings() throws {
        #expect(try passages("search the wiki")["FR-007"]?.text == "Readers look from any page (SRC-006).")
    }

    @Test func fr007PassageIsPlainText() throws {
        let page = entry("X-1", title: "X", plain: "Use <script> & a facilitator.")
        let found = search("facilitator", in: SearchIndex(entries: [page], synonyms: []), filter: SearchFilter(), withPassages: true)
        let passage = try #require(found.first?.passage)
        #expect(passage.text == "Use <script> & a facilitator.")
        #expect(passage.marked == ["facilitator"])
    }

    @Test func fr007LongSentenceIsCutAtBothEnds() throws {
        let filler = Array(repeating: "word", count: 80).joined(separator: " ")
        let cases = [("The facilitator \(filler) end.", false), ("Start \(filler) facilitator \(filler) end.", true)]
        for (plain, starts) in cases {
            let page = entry("X-1", title: "X", plain: plain)
            let found = search("facilitator", in: SearchIndex(entries: [page], synonyms: []), filter: SearchFilter(), withPassages: true)
            let passage = try #require(found.first?.passage)
            #expect(passage.marked == ["facilitator"])
            #expect(passage.text.hasSuffix("…"))
            #expect(passage.text.count <= 245, "\(passage.text.count)")
            #expect(passage.text.hasPrefix("…") == starts)
        }
    }

    @Test func fr007OnlyOnTheResultsPage() throws {
        let popup = search("facilitator", in: try index(), filter: SearchFilter(), withPassages: false)
        #expect(popup.allSatisfy { $0.passage == nil })
        let page = search("facilitator", in: try index(), filter: SearchFilter(), withPassages: true)
        #expect(page.filter { $0.group == .hit }.allSatisfy { $0.passage != nil })
    }

    // MARK: FR-008 related pages

    @Test func fr008NeighboursOfATitleHit() throws {
        let rows = try related("keyholder")
        let found = try ids("keyholder")
        #expect((1...5).contains(rows.count))
        #expect(Set(rows.map(\.id)).isDisjoint(with: found))   // never repeats a hit
        #expect(rows.allSatisfy { $0.note == "linked from STK-023" })
        #expect(rows.count == 5)   // STK-023 has 6 neighbours that are no hit
    }

    @Test func fr008AliasHitCountsBodyHitDoesNot() throws {
        #expect(Set(try related("jedi master").map(\.id)).isSuperset(of: ["FR-001", "DT-001"]))
        #expect(try related("ask").isEmpty)   // ISS-001 says "ask" only in its body
    }

    @Test func fr008OnlyOnTheResultsPage() throws {
        let popup = search("keyholder", in: try index(), filter: SearchFilter(), withPassages: false, withRelated: false)
        #expect(popup.allSatisfy { $0.group == .hit })
        #expect(!(try related("keyholder")).isEmpty)
    }

    // MARK: FR-009 filters

    private func filtered(_ query: String, _ filter: SearchFilter) throws -> [SearchHit] {
        try hits(query, filter)
    }

    @Test func fr009StatusFilterLeavesOnlyThatStatus() throws {
        let everything = Set(try ids("the"))
        let rows = try filtered("the", SearchFilter(statuses: ["accepted"]))
        #expect(everything.isStrictSuperset(of: rows.map(\.id)))
        #expect(!rows.isEmpty && rows.allSatisfy { $0.status == "accepted" })
    }

    @Test func fr009PriorityAndTagFilters() throws {
        #expect(try filtered("the", SearchFilter(priorities: ["must"])).map(\.id).sorted() == ["FR-001", "FR-002"])
        #expect(try filtered("every", SearchFilter(tags: ["navigation"])).map(\.id) == ["FR-004"])
        #expect(try filtered("every", SearchFilter(statuses: ["accepted"], tags: ["navigation"])).isEmpty)   // filters combine
        #expect(try filtered("the", SearchFilter()).count == (try hits("the")).count)   // no filter, no change
    }

    @Test func fr009FiltersSitNextToTheTypeFacets() throws {
        let options = try index().filterOptions
        #expect(options.statuses.map(\.value) == ["accepted", "draft", "open"])
        let labels = Dictionary(uniqueKeysWithValues: (options.statuses + options.priorities + options.tags).map { ($0.value, $0.label) })
        for (value, label) in [("accepted", "accepted"), ("draft", "draft"), ("open", "open"), ("must", "Must"),
                               ("should", "Should"), ("could", "Could"), ("navigation", "navigation")] {
            #expect(labels[value] == label, "\(value)")   // as the wiki writes it
        }
        #expect(options.priorities.map(\.value).prefix(3) == ["must", "should", "could"])
    }

    @Test func fr009NoFilterSyntaxInTheBox() throws {
        #expect(try ids("status:draft") == ids("status draft"))   // the colon is only a word break
    }

    @Test func fr009FiltersApplyToRelatedPages() throws {
        let page = search("keyholder", in: try index(), filter: SearchFilter(statuses: ["accepted"]), withPassages: false)
        #expect(page.filter { $0.group == .related }.allSatisfy { $0.status == "accepted" })
    }
}
