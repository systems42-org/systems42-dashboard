import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport

/// The Swift ranker against `static/search-rank.js`: the answers in `Tests/Golden/<fixture>/queries.json`,
/// written by `scripts/export-search-queries.sh`, for every fixture.
@Suite struct SearchGoldenQueriesTests {
    private func index(_ fixture: String) throws -> SearchIndex {
        let store = WikiStore(root: try Preflight.open(Fixture.url(fixture)))
        return SearchIndex(store: store, metamodel: store.metamodel)
    }

    private func queries(_ fixture: String) throws -> [[String: Any]] {
        let file = try #require(Golden.json(fixture, "queries.json") as? [String: Any])
        return try #require(file["queries"] as? [[String: Any]])
    }

    @Test(arguments: Fixture.names)
    func hitsScoresAndNotesMatch(fixture: String) throws {
        let index = try index(fixture)
        let all = try queries(fixture)
        #expect(all.count >= 60, "\(fixture) has \(all.count) queries")
        for expected in all {
            let query = try #require(expected["q"] as? String)
            let hits = search(query, in: index, filter: SearchFilter(), withPassages: false, withRelated: false)
            let want = try #require(expected["hits"] as? [[String: Any]])
            let got = hits.map { "\($0.id) \($0.score) \($0.note ?? "-")" }
            let wanted = want.map { "\($0["id"] as! String) \($0["score"] as! Int) \($0["note"] as? String ?? "-")" }
            #expect(got == wanted, "\(fixture): \(query)")
        }
    }

    @Test(arguments: Fixture.names)
    func relatedPagesMatch(fixture: String) throws {
        let index = try index(fixture)
        for expected in try queries(fixture) {
            let query = try #require(expected["q"] as? String)
            let related = search(query, in: index).filter { $0.group == .related }
            let want = try #require(expected["related"] as? [[String: Any]])
            #expect(related.map { "\($0.id) \($0.note ?? "-")" } == want.map { "\($0["id"] as! String) \($0["note"] as! String)" },
                    "\(fixture): \(query)")
        }
    }

    @Test func passagesMatch() throws {
        let index = try index("search")
        for expected in try queries("search") {
            let query = try #require(expected["q"] as? String)
            let hits = search(query, in: index, filter: SearchFilter(), withPassages: true, withRelated: false)
            let want = try #require(expected["hits"] as? [[String: Any]])
            for (hit, row) in zip(hits, want) {
                let passage = row["passage"] as? [String: Any]
                #expect(hit.passage?.text == passage?["text"] as? String, "\(query) \(hit.id)")
                let marks = (passage?["marks"] as? [[Int]] ?? []).map { $0[0]..<$0[1] }
                #expect((hit.passage?.marks ?? []) == marks, "\(query) \(hit.id)")
            }
        }
    }

    @Test func filtersMatch() throws {
        let index = try index("search")
        let file = try #require(Golden.json("search", "queries.json") as? [String: Any])
        let cases = try #require(file["filtered"] as? [[String: Any]])
        #expect(cases.count >= 5)
        for expected in cases {
            let query = try #require(expected["q"] as? String)
            let f = try #require(expected["filter"] as? [String: String])
            let filter = SearchFilter(
                statuses: f["status"].map { [$0] } ?? [], priorities: f["priority"].map { [$0] } ?? [], tags: f["tag"].map { [$0] } ?? []
            )
            let hits = search(query, in: index, filter: filter, withPassages: false, withRelated: false)
            #expect(hits.map(\.id) == expected["ids"] as? [String], "\(query) \(f)")
        }
    }
}
