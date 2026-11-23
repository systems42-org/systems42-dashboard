import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

/// The refresh of an open session, and the watcher that drives it. Every wait is bounded by 30 seconds.
@MainActor private var keepAlive: [WikiSession] = []

private struct Copy {
    let folder: URL
    let root: URL

    init() throws {
        root = try Fixture.tempCopy("basic")
        folder = root.deletingLastPathComponent()
    }

    func url(_ path: String) -> URL { root.appending(path: path) }
    func remove() { try? FileManager.default.removeItem(at: folder) }

    func edit(_ path: String, _ change: (String) -> String) throws {
        let file = url(path)
        try change(try String(contentsOf: file, encoding: .utf8)).write(to: file, atomically: true, encoding: .utf8)
    }
}

@MainActor private func open(_ root: URL) async throws -> WikiSession {
    let session = await WikiSession.open(try Preflight.open(root))
    keepAlive.append(session)
    return session
}

@MainActor private func count(_ session: WikiSession, folder: String) -> Int? {
    session.sidebar.flatMap(\.rows).first { $0.section.folders.contains(folder) }?.count
}

/// What a reader sees: sidebar, the rows of every section, and what a search finds.
@MainActor private func look(_ session: WikiSession, search query: String = "book") async -> [String] {
    var lines: [String] = []
    for row in session.sidebar.flatMap(\.rows) {
        lines.append("\(row.section.id) \(row.section.title) \(row.count) \(row.openIssues) \(row.byStatus.map { "\($0.status)=\($0.count)" })")
        let list = ListModel(session: session, section: row.section)
        lines += list.rows.map { "  \($0.ref.folder)/\($0.ref.stem) \($0.title) \($0.status)" }
    }
    let search = session.search
    search.followWiki()
    await search.settle()
    search.query = query
    await search.settle()
    lines += search.quick.map { "found \($0.id)" }
    search.query = ""
    return lines
}

@MainActor private func equalsFreshLoad(_ session: WikiSession, _ root: URL) async throws -> Bool {
    let fresh = try await open(root)
    let mine = await look(session), theirs = await look(fresh)
    #expect(mine == theirs)
    return mine == theirs
}

private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
    let end = ContinuousClock.now + .seconds(30)
    while ContinuousClock.now < end {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

private func newTerm(_ number: Int) -> String {
    """
    ---
    id: DT-\(number)
    type: domain-term
    title: Term \(number)
    status: draft
    created: 2026-09-06
    updated: 2026-09-06
    sources: []
    related: []
    tags: [domain-term]
    aliases: []
    bounded-context: Lending
    agreed: false
    ---

    # Term \(number)

    A book term number \(number).
    """
}

@MainActor @Suite(.serialized) struct RefreshTests {
    @Test func newPageAppears() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        #expect(count(s, folder: "domain-terms") == 4)
        let new = c.url("wiki/domain-terms/DT-005-reservation.md")
        try newTerm(5).write(to: new, atomically: true, encoding: .utf8)
        let before = s.revision
        await s.refresh(changed: [new])
        #expect(count(s, folder: "domain-terms") == 5)
        #expect(s.revision == before + 1)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func deletedSelectedPage() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let ref = PageRef(folder: "functional-requirements", stem: "FR-002-checkout")
        s.select(page: ref)
        #expect(s.selectedPage == ref && !s.selectedPageWasRemoved)
        let file = c.url("wiki/functional-requirements/FR-002-checkout.md")
        try FileManager.default.removeItem(at: file)
        await s.refresh(changed: [file])
        // The page column keeps the reference and says "This page was removed." (PageView). No row is selected.
        #expect(s.selectedPageWasRemoved)
        #expect(s.store.page(ref) == nil)
        let section = try #require(s.metamodel.sections.first { $0.folders.contains("functional-requirements") })
        let list = ListModel(session: s, section: section)
        #expect(!list.rows.contains { $0.ref == ref })
        #expect(PageModel(session: s, ref: ref) == nil)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func renamedPageKeepsLinksHonest() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let old = c.url("wiki/functional-requirements/FR-003-scan-a-book.md")
        let new = c.url("wiki/functional-requirements/FR-003-scan.md")
        let link = Wikilink.all(in: "[[FR-003-scan-a-book]]")
        let before = s.store.resolve(try #require(link.first))
        try FileManager.default.moveItem(at: old, to: new)
        await s.refresh(changed: [old, new])
        let fresh = try await open(c.root)
        let after = s.store.resolve(try #require(link.first))
        #expect(after == fresh.store.resolve(try #require(link.first)))
        #expect(before != after)
        #expect(s.store.page(PageRef(folder: "functional-requirements", stem: "FR-003-scan")) != nil)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func metamodelEditReloadsSections() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let file = c.url("_system/metamodel/frameworks/fw-req42.md")
        try c.edit("_system/metamodel/frameworks/fw-req42.md") { $0.replacingOccurrences(of: "title: \"Functional Requirements\"", with: "title: \"Features Wanted\"") }
        await s.refresh(changed: [file])
        #expect(s.sidebar.flatMap(\.rows).contains { $0.section.title.contains("Features Wanted") })
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func halfWrittenFileDoesNotCrash() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let path = "wiki/domain-terms/DT-001-book.md"
        let ref = PageRef(folder: "domain-terms", stem: "DT-001-book")
        let whole = try String(contentsOf: c.url(path), encoding: .utf8)
        try String(whole.prefix(60)).write(to: c.url(path), atomically: false, encoding: .utf8)
        await s.refresh(changed: [c.url(path)])
        #expect(try #require(s.store.page(ref)).problems.isEmpty == false)
        #expect(try await equalsFreshLoad(s, c.root))
        try whole.write(to: c.url(path), atomically: false, encoding: .utf8)
        await s.refresh(changed: [c.url(path)])
        #expect(try #require(s.store.page(ref)).problems.isEmpty)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func gitCheckoutOfManyFiles() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        var changed: [URL] = []
        for number in 100..<600 {
            let url = c.url("wiki/domain-terms/DT-\(number)-term.md")
            try newTerm(number).write(to: url, atomically: false, encoding: .utf8)
            changed.append(url)
        }
        let before = s.revision
        await s.refresh(changed: changed)
        #expect(s.revision == before + 1)
        #expect(count(s, folder: "domain-terms") == 504)
        #expect(try await equalsFreshLoad(s, c.root))
        // Back to the first state: all gone at once.
        for url in changed { try FileManager.default.removeItem(at: url) }
        await s.refresh(changed: changed)
        #expect(count(s, folder: "domain-terms") == 4)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func refreshEqualsFreshLoad() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let book = "wiki/domain-terms/DT-001-book.md", loan = "wiki/domain-terms/DT-002-loan.md"
        try c.edit(book) { $0.replacingOccurrences(of: "title: Book", with: "title: Volume") }
        await s.refresh(changed: [c.url(book)])
        #expect(try await equalsFreshLoad(s, c.root))
        try FileManager.default.moveItem(at: c.url(loan), to: c.url("wiki/domain-terms/DT-002-lending-loan.md"))
        await s.refresh(changed: [c.url(loan), c.url("wiki/domain-terms/DT-002-lending-loan.md")])
        #expect(try await equalsFreshLoad(s, c.root))
        try FileManager.default.removeItem(at: c.url("wiki/goals"))
        await s.refresh(changed: [c.url("wiki/goals")])
        #expect(try await equalsFreshLoad(s, c.root))
        try newTerm(7).write(to: c.url("wiki/domain-terms/DT-007-x.md"), atomically: true, encoding: .utf8)
        try c.edit("_system/wiki.yaml") { $0 + "\n# edited\n" }
        await s.refresh(changed: [c.url("wiki/domain-terms/DT-007-x.md"), c.url("_system/wiki.yaml")])
        #expect(try await equalsFreshLoad(s, c.root))
        // The folder as a whole may be named, as FSEvents does when it lost track.
        try c.edit(book) { $0.replacingOccurrences(of: "Volume", with: "Tome") }
        await s.refresh(changed: [c.root])
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func aChangeWithSameSizeAndTimeIsStillSeen() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let path = "wiki/domain-terms/DT-001-book.md"
        let file = c.url(path)
        let time = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        try c.edit(path) { $0.replacingOccurrences(of: "title: Book", with: "title: Boot") }
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
        await s.refresh(changed: [file])
        #expect(s.store.page(PageRef(folder: "domain-terms", stem: "DT-001-book"))?.title == "Boot")
    }

    @Test func aChangeDuringARefreshRunsOneMore() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let first = c.url("wiki/domain-terms/DT-005-a.md"), second = c.url("wiki/domain-terms/DT-006-b.md")
        let third = c.url("wiki/domain-terms/DT-007-c.md")
        let before = s.revision
        try newTerm(5).write(to: first, atomically: true, encoding: .utf8)
        async let a: Void = s.refresh(changed: [first])
        try newTerm(6).write(to: second, atomically: true, encoding: .utf8)
        async let b: Void = s.refresh(changed: [second])
        try newTerm(7).write(to: third, atomically: true, encoding: .utf8)
        async let d: Void = s.refresh(changed: [third])
        _ = await (a, b, d)
        // Never more than the running refresh and one that follows it.
        #expect(s.revision - before <= 2)
        #expect(s.revision > before)
        #expect(count(s, folder: "domain-terms") == 7)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func selectionModeAndSearchStayAcrossARefresh() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let section = try #require(s.metamodel.sections.first { $0.folders.contains("functional-requirements") })
        let ref = PageRef(folder: "functional-requirements", stem: "FR-002-checkout")
        s.select(section: section.id)
        s.select(page: ref)
        let mode = s.mode
        let request = SearchRequest(query: "book", filter: SearchFilter())
        s.showSearch(request)
        let list = ListModel(session: s, section: section)
        list.state.filters = ["status": ["draft"]]
        let state = list.state
        try c.edit("wiki/domain-terms/DT-001-book.md") { $0.replacingOccurrences(of: "title: Book", with: "title: Tome") }
        await s.refresh(changed: [c.url("wiki/domain-terms/DT-001-book.md")])
        #expect(s.selectedSection == section.id)
        #expect(s.mode == mode)
        #expect(s.shownSearch == request)
        #expect(list.state == state)
        await s.search.settle()
        #expect(!s.selectedPageWasRemoved)
    }

    @Test func removedFolderIsReportedAndRecovers() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let moved = c.folder.appending(path: "moved")
        try FileManager.default.moveItem(at: c.root, to: moved)
        let before = s.revision
        await s.refresh(changed: [c.root])
        #expect(s.missingParts?.isEmpty == false)
        #expect(s.revision == before)
        try FileManager.default.moveItem(at: moved, to: c.root)
        await s.refresh(changed: [c.root])
        #expect(s.missingParts == nil)
    }

    @Test func aSymlinkOutOfTheWikiIsNotFollowedByARefresh() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        let outside = c.folder.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try newTerm(8).write(to: outside.appending(path: "DT-008-away.md"), atomically: true, encoding: .utf8)
        let link = c.url("wiki/escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let single = c.url("wiki/domain-terms/DT-009-link.md")
        try FileManager.default.createSymbolicLink(at: single, withDestinationURL: outside.appending(path: "DT-008-away.md"))
        await s.refresh(changed: [link, single, outside])
        #expect(!s.store.folders().contains("escape"))
        #expect(s.store.page(PageRef(folder: "domain-terms", stem: "DT-009-link")) == nil)
        #expect(count(s, folder: "domain-terms") == 4)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    // MARK: with the watcher

    @Test func editsReachTheSessionByThemselves() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        s.startWatching()
        defer { s.stopWatching() }
        try await Task.sleep(for: .milliseconds(300))
        try c.edit("wiki/domain-terms/DT-001-book.md") { $0.replacingOccurrences(of: "title: Book", with: "title: Tome") }
        let ref = PageRef(folder: "domain-terms", stem: "DT-001-book")
        #expect(await waitUntil { s.store.page(ref)?.title == "Tome" })
        try await Task.sleep(for: .seconds(1.5))
        #expect(s.revision == 1)
        #expect(try await equalsFreshLoad(s, c.root))
    }

    @Test func removingTheFolderShowsItWhileWatching() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        s.startWatching()
        defer { s.stopWatching() }
        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.removeItem(at: c.root)
        #expect(await waitUntil { s.missingParts != nil })
    }

    @Test func watchingChangesNoFile() async throws {
        let c = try Copy()
        defer { c.remove() }
        let s = try await open(c.root)
        try await assertUnchangedAsync(c.root) {
            s.startWatching()
            try await Task.sleep(for: .seconds(1))
            await s.refresh(changed: [c.url("wiki/domain-terms/DT-001-book.md")])
            s.stopWatching()
        }
    }

    @Test func aClosedSessionIsFreed() async throws {
        let c = try Copy()
        defer { c.remove() }
        weak var freed: WikiSession?
        do {
            let s = await WikiSession.open(try Preflight.open(c.root))
            freed = s
            s.startWatching()
            try await Task.sleep(for: .milliseconds(300))
            try c.edit("wiki/domain-terms/DT-001-book.md") { $0 + "\nmore\n" }
            #expect(await waitUntil { s.revision > 0 })
            s.stopWatching()
        }
        // The loop of a refresh holds the session until it ends.
        #expect(await waitUntil { freed == nil })
        // Events that still arrive meet no session.
        try c.edit("wiki/domain-terms/DT-001-book.md") { $0 + "\nmore\n" }
        try await Task.sleep(for: .milliseconds(800))
    }

    @Test func aSessionThatNeverStoppedIsFreedToo() async throws {
        let c = try Copy()
        defer { c.remove() }
        weak var freed: WikiSession?
        do {
            let s = await WikiSession.open(try Preflight.open(c.root))
            freed = s
            s.startWatching()
        }
        #expect(await waitUntil { freed == nil })
    }
}
