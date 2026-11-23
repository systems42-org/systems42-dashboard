import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport

@Suite struct SearchIndexTests {
    private func index(_ fixture: String) throws -> SearchIndex {
        let store = WikiStore(root: try Preflight.open(Fixture.url(fixture)))
        return SearchIndex(store: store, metamodel: store.metamodel)
    }

    /// The encoded index equals what the Go dashboard answers on `/search.json`.
    @Test(arguments: Fixture.names)
    func indexMatchesGolden(fixture: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try JSONSerialization.jsonObject(with: encoder.encode(try index(fixture))) as? [String: Any]
        let golden = try #require(Golden.json(fixture, "search.json") as? [String: Any])
        let mine = try #require(encoded)
        let mineRecords = try #require(mine["records"] as? [[String: Any]])
        let goldenRecords = try #require(golden["records"] as? [[String: Any]])
        #expect(mineRecords.count == goldenRecords.count)
        // `url` is left out: it is the route of the page in the web dashboard, the app opens pages by `ref`
        for (a, b) in zip(mineRecords, goldenRecords) {
            #expect(NSDictionary(dictionary: a) == NSDictionary(dictionary: b.filter { $0.key != "url" }), "\(b["id"] ?? "?")")
        }
        #expect(golden["synonyms"] as? NSArray == mine["synonyms"] as? NSArray)
    }

    @Test func indexHoldsPlainTextOfEveryPage() throws {
        for fixture in Fixture.names {
            let entries = try index(fixture).entries
            #expect(entries.contains { !$0.plain.isEmpty }, "\(fixture)")
            #expect(entries.allSatisfy { $0.ref != nil })
        }
    }

    @Test func indexDecodedFromJSONRanksLikeTheIndexOfTheStore() throws {
        let data = try Data(contentsOf: Golden.url("search", "search.json"))
        let decoded = try JSONDecoder().decode(SearchIndex.self, from: data)
        let built = try index("search")
        #expect(decoded.entries.count == built.entries.count)
        for query in ["keyholder", "keyholdr", "moderator", "who starts the app", "the"] {
            let a = search(query, in: decoded, filter: SearchFilter(), withPassages: true)
            let b = search(query, in: built, filter: SearchFilter(), withPassages: true)
            #expect(a.map(\.id) == b.map(\.id), "\(query)")
            #expect(a.map(\.passage) == b.map(\.passage), "\(query)")
        }
    }

    // MARK: plain text of a body

    /// Expected text from `Plain` of the Go dashboard on the same body.
    @Test func plainTextOfABody() throws {
        let body = """
        # Title line

        > follows [[MADR]]

        > [!note] Callout title
        > Quoted **text** here.

        **Problem.** The [[STK-023-keyholder]] asks the [[DT-001|moderator]] to
        start the <b>session</b> and read [the guide](http://x.y/z).
        It wraps over two lines. See [[SRC-001]] and [[FR-007-search-the-wiki#part]].

        - first *item* with `code`
        - [ ] open task
          continues here

        1. step one
        2) step two

        | Name | Value |
        |------|-------|
        | a | [[FR-007-search-the-wiki]] |

        ```
        [[not a link]] **kept**
        ```

        ---
        Last line with a_b and 2 * 3 * 4.
        """
        let entry = try entry(ofBody: body)
        #expect(entry.plain == """
        Quoted text here.
        The Keyholder asks the moderator to start the session and read the guide. It wraps over two lines. See SRC-001 and Search the wiki.
        first item with code
        open task
        continues here
        step one
        step two
        Name Value
        a Search the wiki
        not a link kept
        --- Last line with a_b and 2 * 3 * 4.
        """)
    }

    /// Adds one page to a copy of the fixture `search` and returns its entry.
    private func entry(ofBody body: String) throws -> SearchEntry {
        let copy = try Fixture.tempCopy("search")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let page = "---\nid: ISS-900\ntype: issue\ntitle: Plain text\nstatus: draft\n---\n" + body
        try page.write(to: copy.appending(path: "wiki/issues/ISS-900-plain-text.md"), atomically: true, encoding: .utf8)
        let store = WikiStore(root: try Preflight.open(copy))
        let built = SearchIndex(store: store, metamodel: store.metamodel)
        return try #require(built.entries.first { $0.id == "ISS-900" })
    }

    /// The dashboard escapes the passage for HTML. The Swift passage is text: the characters stay as written.
    /// (A real tag such as `<script>` never reaches the index, `Plain` removes it, as in the dashboard.)
    @Test func passageIsPlainText() throws {
        let page = try entry(ofBody: "Say \"hi\" & 5 < 6, facilitator.\n")
        let found = hits("facilitator", [page])
        let passage = try #require(found.first?.passage)
        #expect(passage.text == "Say \"hi\" & 5 < 6, facilitator.")
        #expect(passage.marked == ["facilitator"])
        let withTag = try entry(ofBody: "Use <script>alert(1)</script> and the facilitator.")
        #expect(withTag.plain == "Use alert(1) and the facilitator.")
    }

    /// Bodies of 2 MB or more, each in a shape that makes a careless scanner copy or rescan the rest
    /// of the page for every opening mark.
    @Test(arguments: [
        ("[[", 1_000_000), ("[[a", 700_000), ("[[a|b", 450_000), ("[[a#b|", 350_000), ("[", 2_000_000), ("![", 1_000_000),
        ("<", 2_000_000), ("`", 2_000_000), ("**", 1_000_000), ("> ", 1_000_000), ("- ", 1_000_000), ("|---|---\n", 250_000),
        ("word\n", 450_000), ("```\n", 500_000), (" ", 2_000_000), ("[](", 700_000), ("> follows [[a\n", 150_000),
        ("é\n", 1_000_000), ("é ", 1_000_000),
    ])
    func hostileBodiesBuildInBoundedTime(piece: String, count: Int) throws {
        let body = String(repeating: piece, count: count) + "x"
        #expect(body.utf8.count >= 1_000_000)
        let clock = ContinuousClock()
        var built: SearchEntry?
        let took = try clock.measure { built = try entry(ofBody: body) }
        #expect(built != nil)
        // The slowest body takes about 5 s in a debug build. The CI machine is up to 7 times
        // slower while the other tests run beside it. A quadratic scan takes minutes.
        #expect(took < .seconds(90), "\(piece.debugDescription): \(took)")
    }

    // MARK: ranking, string rules

    private func entry(_ id: String, title: String, plain: String = "", aliases: [String] = []) -> SearchEntry {
        SearchEntry(id: id, type: "Issue", title: title, aliases: aliases, plain: plain)
    }

    private func hits(_ query: String, _ entries: [SearchEntry], synonyms: [[String]] = []) -> [SearchHit] {
        search(query, in: SearchIndex(entries: entries, synonyms: synonyms), filter: SearchFilter(), withPassages: true)
    }

    @Test func notes() {
        let entries = [
            entry("A-1", title: "Keyholder", plain: "alpha beta"),
            entry("A-2", title: "Other", plain: "The keyholder started it", aliases: ["Gatekeeper"]),
            entry("A-3", title: "Third", plain: "alpha beta gamma"),
        ]
        let partial = hits("alpha beta gamma", entries)
        #expect(partial.first { $0.id == "A-3" }?.note == nil)
        #expect(partial.first { $0.id == "A-1" }?.note == "matches 2 of 3 words")
        #expect(hits("keyholdr", entries).first { $0.id == "A-1" }?.note == "typo: keyholdr → Keyholder")
        #expect(hits("starts", entries).first { $0.id == "A-2" }?.note == "word form: starts → started")
        #expect(hits("gatekeeper", entries).first { $0.id == "A-2" }?.note == "via alias of Other")
        #expect(hits("keyholder", entries).allSatisfy { $0.note == nil })
        #expect(hits("keyholder", entries, synonyms: [["keyholder", "gatekeeper"]]).first { $0.id == "A-2" }?.note == nil)
    }

    @Test func relatedNote() {
        let entries = [
            SearchEntry(id: "A-1", type: "Issue", title: "Keyholder", links: ["A-2", "A-3"]),
            SearchEntry(id: "A-2", type: "Issue", title: "Neighbour"),
            SearchEntry(id: "A-3", type: "Issue", title: "Keyholder notes", links: ["A-1"]),
        ]
        let related = hits("keyholder", entries).filter { $0.group == .related }
        #expect(related.map(\.id) == ["A-2"])   // A-3 is a hit already
        #expect(related.map(\.note) == ["linked from A-1"])
        #expect(related.allSatisfy { $0.passage == nil })
    }

    @Test func finalSigmaLowersLikeJavaScript() {
        // "ΟΔΟΣ".toLowerCase() is "οδος" with a final sigma. A plain per-letter mapping gives "οδοσ".
        let found = hits("ΟΔΟΣ", [entry("A-1", title: "Other", plain: "Der οδος ist weit.")])
        #expect(found.first?.id == "A-1")
        #expect(found.first?.note == nil)
    }

    @Test func queryIsNormalisedLikeJavaScript() {
        // a decomposed é in the query meets a composed é in the page
        let found = hits("cafe\u{301}", [entry("A-1", title: "Café")])
        #expect(found.first?.id == "A-1" && found.first?.note == nil)
        #expect(matchKind(query: "cafe\u{301}", word: "caf\u{e9}") == nil)   // matchWord itself compares code points
    }

    @Test func passageMarksCountUTF16Units() throws {
        let found = hits("facilitator", [entry("A-1", title: "Other", plain: "😀 the facilitator here.")])
        let passage = try #require(found.first?.passage)
        #expect(passage.marks == [7..<18])   // the emoji is two UTF-16 units
        #expect(passage.marked == ["facilitator"])
    }

    @Test func attributedPassageMarksTheWords() throws {
        let found = hits("facilitator", [entry("A-1", title: "Other", plain: "Works with the facilitator.")])
        let passage = try #require(found.first?.passage)
        let marked = passage.attributed.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(marked.map { String(passage.attributed[$0.range].characters) } == ["facilitator"])
    }

    // MARK: bounds

    @Test func hugeQueriesAreBounded() throws {
        let index = try self.index("search")
        let clock = ContinuousClock()
        let took = clock.measure {
            _ = search(String(repeating: "x", count: 10_000), in: index)
            _ = search(String(repeating: "keyholder ", count: 500), in: index)
            _ = search(String(repeating: "stakholdrs workshop ", count: 300), in: index)
            _ = search(String(repeating: "!?.,;:- ", count: 1_000), in: index)
            _ = search(String(repeating: "\u{301}", count: 10_000), in: index)
            _ = search("", in: index)
        }
        #expect(took < .seconds(10), "\(took)")
        #expect(search("!?.,;:-", in: index).isEmpty)
        #expect(search(String(repeating: "x", count: 10_000), in: index).isEmpty)
    }

    @Test func aQueryOfManyWordsUsesTheFirstSixteen() throws {
        let index = try self.index("search")
        let first16 = Array(repeating: "keyholder", count: 16).joined(separator: " ")
        let many = Array(repeating: "keyholder", count: 500).joined(separator: " ")
        let a = search(first16, in: index).map(\.id)
        #expect(!a.isEmpty)
        #expect(search(many, in: index).map(\.id) == a)
    }

    @Test func anEmptyIndexFindsNothing() {
        #expect(search("keyholder", in: SearchIndex(entries: [], synonyms: [])).isEmpty)
    }

    @Test func searchIsFastEnough() {
        // 2,000 generated pages of about 45 words from a vocabulary of 1,500 words of 3 to 11 letters
        var state: UInt64 = 42
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let vocabulary = (0..<1_500).map { _ in String((0..<(3 + next() % 9)).map { _ in letters[next() % letters.count] }) }
        func words(_ n: Int) -> [String] { (0..<n).map { _ in vocabulary[next() % vocabulary.count] } }
        let entries = (0..<2_000).map { i in
            SearchEntry(
                id: "FR-\(i)", type: "Functional requirement", title: words(3).joined(separator: " "),
                aliases: i % 10 == 0 ? [words(2).joined(separator: " ")] : [],
                plain: (0..<4).map { _ in words(10).joined(separator: " ") + "." }.joined(separator: " "),
                fields: ["tags": [words(1)[0]], "priority": ["must"]], links: ["FR-\(next() % 2_000)"]
            )
        }
        let index = SearchIndex(entries: entries, synonyms: [])
        let queries = (0..<100).map { i -> String in
            var w = words(1 + i % 3)
            if i % 2 == 0, w[0].count > 4 { w[0].remove(at: w[0].index(w[0].startIndex, offsetBy: 2)) }
            return w.joined(separator: " ")
        }
        let clock = ContinuousClock()
        var total = 0
        let took = clock.measure {
            for q in queries { total += search(q, in: index, filter: SearchFilter(), withPassages: true).count }
        }
        #expect(total > 0)
        // About 1.2 s in a debug build on a development machine. The CI machine is up to
        // 7 times slower while the other tests run beside it.
        #expect(took < .seconds(30), "\(took)")
    }
}
