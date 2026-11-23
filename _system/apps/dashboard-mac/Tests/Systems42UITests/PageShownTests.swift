import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

/// What the page column does when the wiki is replaced: it keeps its content until the new content is ready.
@MainActor private var held: [WikiSession] = []

private func edit(_ root: URL, _ path: String, _ change: (String) -> String) throws -> URL {
    let file = root.appending(path: path)
    try change(try String(contentsOf: file, encoding: .utf8)).write(to: file, atomically: true, encoding: .utf8)
    return file
}

@MainActor private func open(_ root: URL) async throws -> WikiSession {
    let session = await WikiSession.open(try Preflight.open(root))
    held.append(session)
    return session
}

@MainActor private final class Progress {
    var done = false
    var blank = false
}

/// Runs `follow()` and notes whether the model was missing at any pause.
@MainActor private func following(_ shown: PageShown, keeping: Bool = true) async {
    let progress = Progress()
    let task = Task { @MainActor in
        await shown.follow()
        progress.done = true
    }
    while !progress.done {
        if shown.model == nil { progress.blank = true }
        await Task.yield()
    }
    await task.value
    if keeping { #expect(!progress.blank, "the page went blank during the refresh") }
}

@MainActor @Suite(.serialized) struct PageShownTests {
    private let checkout = PageRef(folder: "functional-requirements", stem: "FR-002-checkout")

    @Test func anotherPageChangedKeepsTheModel() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let shown = PageShown(session: s, ref: checkout)
        await shown.follow()
        let first = try #require(shown.model)
        #expect(first.isLoaded)
        // A page that FR-002 does not mention.
        let file = try edit(root, "wiki/stakeholders/STK-002-reader.md") { $0 + "\nAnother sentence.\n" }
        await s.refresh(changed: [file])
        #expect(first.isStale)
        await following(shown)
        #expect(shown.model === first)
        #expect(!first.isStale)
        #expect(first.isLoaded)
    }

    @Test func theShownPageChangedBringsNewContentWithoutBlank() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let shown = PageShown(session: s, ref: checkout)
        await shown.follow()
        let first = try #require(shown.model)
        let file = try edit(root, "wiki/functional-requirements/FR-002-checkout.md") { $0.replacingOccurrences(of: "title: Checkout", with: "title: Check out") }
        await s.refresh(changed: [file])
        await following(shown)
        let second = try #require(shown.model)
        #expect(second !== first)
        #expect(second.page.title == "Check out")
        #expect(second.isLoaded && !second.isStale)
    }

    @Test func aPageThatLinksToAChangedTitleIsNewToo() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let shown = PageShown(session: s, ref: checkout)
        await shown.follow()
        let first = try #require(shown.model)
        // FR-002 relates to its parent. A new title of the parent shows in the relations panel.
        let file = try edit(root, "wiki/functional-requirements/FR-001-lending.md") { $0.replacingOccurrences(of: "title: Book Lending", with: "title: Book Lending 2") }
        await s.refresh(changed: [file])
        let fresh = try #require(PageModel(session: s, ref: checkout))
        await following(shown)
        #expect(fresh.fingerprint != first.fingerprint, "the parent's title is part of what the page shows")
        #expect(shown.model !== first)
        #expect(shown.model?.fingerprint == fresh.fingerprint)
    }

    @Test func aRemovedPageIsSaidToBeRemovedAndComesBack() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let shown = PageShown(session: s, ref: checkout)
        await shown.follow()
        let file = root.appending(path: "wiki/functional-requirements/FR-002-checkout.md")
        let text = try String(contentsOf: file, encoding: .utf8)
        try FileManager.default.removeItem(at: file)
        await s.refresh(changed: [file])
        await following(shown, keeping: false)
        #expect(shown.model == nil && shown.removed)
        try text.write(to: file, atomically: true, encoding: .utf8)
        await s.refresh(changed: [file])
        await following(shown, keeping: false)
        #expect(shown.model != nil && !shown.removed)
    }

    @Test func aNewerRevisionDuringTheRenderKeepsTheOldContent() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let shown = PageShown(session: s, ref: checkout)
        await shown.follow()
        let first = try #require(shown.model)
        let file = try edit(root, "wiki/functional-requirements/FR-002-checkout.md") { $0.replacingOccurrences(of: "title: Checkout", with: "title: Check out") }
        await s.refresh(changed: [file])
        let task = Task { await shown.follow() }
        task.cancel()
        await task.value
        #expect(shown.model === first)
    }

    // MARK: Diagrams

    /// A diagram source that does not change draws no new page, however often the wiki is replaced.
    @Test func anUnchangedDiagramAsksTheBudgetForNothing() async throws {
        let root = try Fixture.tempCopy("domain-model")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let term = try #require(s.store.pages(in: "domain-terms").first { $0.id == "DT-001" })
        let diagram = PageDiagramModel(session: s, ref: term.ref)
        await diagram.load()
        let before = try #require(diagram.source)

        let budget = DiagramBudget()
        let view = DiagramViewModel(budget: budget)
        await view.show(DiagramContent(before), dark: false)
        #expect(budget.asks == 1 && budget.pageCount == 1)

        // A page far from the term changes: new revision, same diagram.
        let file = try edit(root, "wiki/domain-terms/DT-004-review-policy.md") { $0 + "\nMore text.\n" }
        await s.refresh(changed: [file])
        await diagram.load()
        let after = try #require(diagram.source)
        #expect(after == before)
        await view.show(DiagramContent(after), dark: false)
        #expect(budget.asks == 1, "the same source asked for another draw")
        #expect(budget.pageCount == 1)

        // A change of the diagram itself draws again, on the same page.
        let renamed = try edit(root, "wiki/domain-terms/DT-001-customer.md") { $0.replacingOccurrences(of: "title: Customer", with: "title: Client") }
        await s.refresh(changed: [renamed])
        await diagram.load()
        let changed = try #require(diagram.source)
        #expect(changed != before)
        await view.show(DiagramContent(changed), dark: false)
        #expect(budget.asks == 2 && budget.pageCount == 1)
        view.close()
    }
}
