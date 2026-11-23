import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

func openStore(_ url: URL) throws -> WikiStore {
    WikiStore(root: try Preflight.open(url))
}

func openFixture(_ name: String) throws -> WikiStore {
    try openStore(Fixture.url(name))
}

/// A temp copy of a fixture and a store on it.
func tempStore(_ name: String) throws -> (url: URL, store: WikiStore) {
    let url = try Fixture.tempCopy(name)
    return (url, try openStore(url))
}

func ref(_ folder: String, _ stem: String) -> PageRef {
    PageRef(folder: folder, stem: stem)
}

private func goldenPages(_ name: String) throws -> [String: [String: Any]] {
    try #require(Golden.json(name, "pages.json") as? [String: [String: Any]])
}

private func ids(_ store: WikiStore, _ refs: [PageRef]) -> [String] {
    refs.compactMap { store.page($0)?.id }.sorted()
}

@Suite struct PageModelTests {
    @Test func readsAllPages() throws {
        let store = try openFixture("basic")
        let total = store.folders().reduce(0) { $0 + store.pages(in: $1).count }
        #expect(total == 15)
        #expect(store.folders() == ["decisions", "domain-terms", "functional-requirements", "goals", "stakeholders"])
    }

    @Test(arguments: Fixture.names)
    func everyGoldenPageIsRead(name: String) throws {
        let store = try openFixture(name)
        let read = store.folders().flatMap { store.pages(in: $0) }.map(\.id).sorted()
        let golden = try goldenPages(name).keys.sorted()
        #expect(read == golden)
    }

    @Test func pagesComeInFileNameOrder() throws {
        let stems = try openFixture("basic").pages(in: "domain-terms").map(\.ref.stem)
        #expect(stems == ["DT-001-book", "DT-002-loan", "DT-003-member", "DT-004-shelf"])
    }

    @Test func pageById() throws {
        let store = try openFixture("basic")
        let page = try #require(store.page(id: "FR-002"))
        #expect(page.ref.stem == "FR-002-checkout")
        #expect(page.ref.folder == "functional-requirements")
        #expect(page.title == "Checkout")
        #expect(page.fields["priority"] == .text("Must"))
        #expect(page.type == "functional-requirement")
        #expect(page.status == "accepted")
        #expect(page.body.hasPrefix("\n# Checkout"))
        #expect(!page.body.contains("priority: Must"))
        #expect(page.problems.isEmpty)
        #expect(store.page(ref("functional-requirements", "FR-002-checkout"))?.id == "FR-002")
        #expect(store.page(id: "FR-999") == nil)
    }

    @Test func listFieldsKeepTheirKind() throws {
        let page = try #require(try openFixture("basic").page(id: "FR-002"))
        #expect(page.fields["parent"] == .links([Wikilink(target: "FR-001-lending", label: nil, heading: nil)]))
        #expect(page.fields["tags"] == .list(["functional-requirement"]))
        #expect(page.fields["sources"] == .list([]))
        #expect(page.fields["order"] == .text("1"))
        #expect(page.fields["created"] == .text("2026-09-06"))
    }

    @Test func resolveByStemIdAndAlias() throws {
        let store = try openFixture("basic")
        let checkout = LinkTarget.page(ref("functional-requirements", "FR-002-checkout"))
        func link(_ target: String, label: String? = nil, heading: String? = nil) -> Wikilink {
            Wikilink(target: target, label: label, heading: heading)
        }
        #expect(store.resolve(link("FR-002-checkout")) == checkout)
        #expect(store.resolve(link("FR-002")) == checkout)
        #expect(store.resolve(link("FR-002", label: "Checkout")) == checkout)
        #expect(store.resolve(link("FR-002", heading: "Story")) == checkout)
        #expect(store.resolve(link("wiki/functional-requirements/FR-002-checkout")) == checkout)
        #expect(store.resolve(link("ADR-0001")) == .page(ref("decisions", "DR-001-carts-expire-after-a-day")))
        #expect(store.resolve(link("MADR")) == .anchor("MADR"))
        #expect(store.resolve(link("madr")) == .anchor("MADR"))
        #expect(store.resolve(link("NOPE-999")) == .missing)
    }

    @Test func stemBeatsIdAndIdBeatsAlias() throws {
        let (url, store) = try tempStore("basic")
        let dir = url.appending(path: "wiki/domain-terms")
        // A page whose alias is the id of another page, and whose id is a stem.
        try "---\nid: DT-001-book\ntitle: Imposter\naliases: [DT-002, Shared]\n---\n"
            .write(to: dir.appending(path: "DT-050-imposter.md"), atomically: true, encoding: .utf8)
        store.reload(changed: nil)
        #expect(store.resolve(Wikilink(target: "DT-001-book", label: nil, heading: nil))
            == .page(ref("domain-terms", "DT-001-book")))
        #expect(store.resolve(Wikilink(target: "DT-002", label: nil, heading: nil))
            == .page(ref("domain-terms", "DT-002-loan")))
        #expect(store.resolve(Wikilink(target: "Shared", label: nil, heading: nil))
            == .page(ref("domain-terms", "DT-050-imposter")))
    }

    @Test func anchorsAndMetamodelNamesResolve() throws {
        let store = try openFixture("basic")
        func link(_ target: String) -> Wikilink { Wikilink(target: target, label: nil, heading: nil) }
        #expect(store.resolve(link("PAM")) == .anchor("PAM"))
        #expect(store.resolve(link("story-mapping")) == .anchor("Story Mapping"))
        #expect(store.resolve(link("type-goal")) == .metamodel("goal"))
        #expect(store.resolve(link("rel-parent")) == .metamodel("parent"))
        #expect(store.resolve(link("functional-requirement")) == .metamodel("functional-requirement"))
    }

    @Test func sourcesResolveByStemAndId() throws {
        let (url, store) = try tempStore("basic")
        try "---\nid: SRC-001\ntitle: Interview\n---\nSummary\n".write(
            to: url.appending(path: "raw/sources/SRC-001-interview.md"), atomically: true, encoding: .utf8)
        store.reload(changed: nil)
        func link(_ target: String) -> Wikilink { Wikilink(target: target, label: nil, heading: nil) }
        #expect(store.resolve(link("SRC-001-interview")) == .source("SRC-001-interview"))
        #expect(store.resolve(link("SRC-001")) == .source("SRC-001-interview"))
        #expect(store.resolve(link("raw/sources/SRC-001-interview")) == .source("SRC-001-interview"))
        #expect(store.resolve(link("SRC-404")) == .missing)
    }

    @Test(arguments: Fixture.names)
    func linksMatchGolden(name: String) throws {
        let store = try openFixture(name)
        for (id, entry) in try goldenPages(name) {
            let page = try #require(store.page(id: id), "\(name) \(id)")
            let relations = store.relations(of: page.ref)
            #expect(ids(store, relations.linksTo) == entry["links_to"] as? [String], "\(name) \(id) links_to")
            // The golden export files every block of the trace panel under linked_from.
            #expect(ids(store, relations.linkedFrom + relations.traced) == entry["linked_from"] as? [String], "\(name) \(id) linked_from")
        }
    }

    @Test func linksFromGroupByField() throws {
        let store = try openFixture("basic")
        let from = store.linksFrom(ref("functional-requirements", "FR-002-checkout"))
        #expect(from["parent"] == [ref("functional-requirements", "FR-001-lending")])
        #expect(from["text"] == [
            ref("functional-requirements", "FR-001-lending"),
            ref("functional-requirements", "FR-003-scan-a-book"),
            ref("functional-requirements", "FR-004-confirm-loan"),
        ])
        #expect(from["tags"] == nil)
        #expect(store.linksFrom(ref("nope", "nope")).isEmpty)
    }

    @Test func linksToGroupByTheFieldThatLinks() throws {
        let store = try openFixture("basic")
        let to = store.linksTo(ref("functional-requirements", "FR-001-lending"))
        #expect(to["parent"]?.contains(ref("functional-requirements", "FR-002-checkout")) == true)
        #expect(to["text"]?.contains(ref("functional-requirements", "FR-002-checkout")) == true)
        for refs in to.values { #expect(refs == refs.sorted { $0.stem < $1.stem }) }
    }

    @Test func foldedViewDropsPagesWhoseLinkIsShownTwice() throws {
        // DT-001 links to DT-002 and DT-004 and is linked from FR-003 and STK-002 (golden).
        let store = try openFixture("basic")
        let relations = store.relations(of: ref("domain-terms", "DT-001-book"))
        #expect(ids(store, relations.linksTo) == ["DT-002", "DT-004"])
        #expect(ids(store, relations.linkedFrom) == ["FR-003", "STK-002"])
        // The raw view keeps a page that is on both sides.
        let rawFrom = store.linksFrom(ref("domain-terms", "DT-001-book")).values.flatMap { $0 }
        let rawTo = store.linksTo(ref("domain-terms", "DT-001-book")).values.flatMap { $0 }
        #expect(Set(rawFrom).isSuperset(of: relations.linksTo))
        #expect(Set(rawTo).isSuperset(of: relations.linkedFrom))
    }

    @Test func statusSplit() throws {
        let store = try openFixture("basic")
        func count(_ folder: String, _ status: String) -> Int {
            store.pages(in: folder).filter { $0.status == status }.count
        }
        #expect(count("functional-requirements", "accepted") == 5)
        #expect(count("functional-requirements", "draft") == 1)
        #expect(count("domain-terms", "accepted") == 3)
        #expect(count("domain-terms", "draft") == 1)
    }

    @Test func reloadSeesAnEdit() throws {
        let (url, store) = try tempStore("basic")
        let file = url.appending(path: "wiki/functional-requirements/FR-002-checkout.md")
        #expect(store.page(id: "FR-002")?.title == "Checkout")
        let text = try String(contentsOf: file, encoding: .utf8)
        try text.replacingOccurrences(of: "title: Checkout", with: "title: Pay at the desk")
            .write(to: file, atomically: true, encoding: .utf8)
        store.reload(changed: [file])
        #expect(store.page(id: "FR-002")?.title == "Pay at the desk")
    }

    @Test func reloadAllSeesAddedAndRemovedFiles() throws {
        let (url, store) = try tempStore("basic")
        let dir = url.appending(path: "wiki/domain-terms")
        try "---\nid: DT-077\ntitle: New\n---\n[[DT-001-book]]\n"
            .write(to: dir.appending(path: "DT-077-new.md"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: dir.appending(path: "DT-004-shelf.md"))
        store.reload(changed: nil)
        #expect(store.page(id: "DT-077")?.title == "New")
        #expect(store.page(id: "DT-004") == nil)
        #expect(store.pages(in: "domain-terms").count == 4)
        #expect(store.linksTo(ref("domain-terms", "DT-001-book"))["text"]?.contains(ref("domain-terms", "DT-077-new")) == true)
    }

    @Test func aNewFolderAppearsAfterReload() throws {
        let (url, store) = try tempStore("basic")
        let dir = url.appending(path: "wiki/issues")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nid: ISS-001\ntitle: Q\nstatus: open\n---\n".write(
            to: dir.appending(path: "ISS-001-q.md"), atomically: true, encoding: .utf8)
        store.reload(changed: nil)
        #expect(store.folders().contains("issues"))
        #expect(store.page(id: "ISS-001")?.title == "Q")
    }

    @Test func openIssuesForAPage() throws {
        let store = try openFixture("search")
        let golden = try goldenPages("search")
        let openIssues = golden.values.filter { ($0["id"] as? String)?.hasPrefix("ISS-") == true && $0["status"] as? String == "open" }
        #expect(!openIssues.isEmpty)
        var expected: [String: Set<String>] = [:]
        for issue in openIssues {
            for target in issue["links_to"] as? [String] ?? [] {
                expected[target, default: []].insert(issue["id"] as? String ?? "")
            }
        }
        #expect(expected.count >= 2)
        for id in golden.keys {
            let page = try #require(store.page(id: id))
            #expect(Set(store.openIssues(for: page.ref).map(\.id)) == expected[id, default: []], "\(id)")
        }
    }

    @Test func storeChangesNoFile() throws {
        let copy = try Fixture.tempCopy("basic")
        assertUnchanged(copy) {
            let store = try? openStore(copy)
            for folder in store?.folders() ?? [] {
                for page in store?.pages(in: folder) ?? [] {
                    _ = store?.linksFrom(page.ref)
                    _ = store?.linksTo(page.ref)
                    _ = store?.relations(of: page.ref)
                    _ = store?.openIssues(for: page.ref)
                }
            }
            store?.reload(changed: nil)
            _ = store?.page(id: "FR-002")
        }
    }

    @Test func concurrentReadsAreSafe() throws {
        let store = try openFixture("arc42-views")
        let all = store.folders().flatMap { store.pages(in: $0) }
        DispatchQueue.concurrentPerform(iterations: 64) { i in
            let page = all[i % all.count]
            _ = store.linksTo(page.ref)
            _ = store.relations(of: page.ref)
            _ = store.page(id: page.id)
            if i % 16 == 0 { store.reload(changed: nil) }
        }
        #expect(store.pages(in: "building-blocks").count > 0)
    }
}

@Suite struct WikilinkTests {
    @Test func parsesTargetLabelAndHeading() {
        let links = Wikilink.all(in: "a [[X-1]] b [[X-2|Two]] c [[X-3#Part]] d [[ X-4 #Part|Four ]]")
        #expect(links == [
            Wikilink(target: "X-1", label: nil, heading: nil),
            Wikilink(target: "X-2", label: "Two", heading: nil),
            Wikilink(target: "X-3", label: nil, heading: "Part"),
            Wikilink(target: "X-4", label: "Four", heading: "Part"),
        ])
    }

    @Test func ignoresWhatIsNotALink() {
        #expect(Wikilink.all(in: "[[]] [[#h]] [[|x]] [[a]b]] [[open").isEmpty)
        #expect(Wikilink.all(in: "[x](y) [single]").isEmpty)
    }

    @Test func aLinkMayHoldAnOpeningBracketPair() {
        #expect(Wikilink.all(in: "[[a [[b]]").map(\.target) == ["a [[b"])
    }

    @Test func hugeRunsOfBracketsFinish() {
        let text = String(repeating: "[[", count: 300_000) + "]" + String(repeating: "[[a#]", count: 100_000)
        #expect(Wikilink.all(in: text).isEmpty)
    }
}
