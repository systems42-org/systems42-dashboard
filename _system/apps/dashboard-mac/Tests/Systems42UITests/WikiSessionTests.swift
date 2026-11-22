import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor
private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

@MainActor @Suite struct WikiSessionTests {
    private func requirementsSection(_ s: WikiSession) throws -> Section {
        try #require(s.metamodel.sections.first { $0.folders.contains("functional-requirements") })
    }

    private func existingRefs(_ s: WikiSession) -> [PageRef] {
        s.store.pages(in: "functional-requirements").map(\.ref)
    }

    @Test func openSelectsSectionAndPage() async throws {
        let s = try await session("basic")
        let ref = try #require(existingRefs(s).dropFirst().first)
        s.open(.page(ref))
        #expect(s.selectedSection == (try requirementsSection(s)).id)
        #expect(s.selectedPage == ref)
    }

    @Test func openIgnoresTargetsThatAreNotPages() async throws {
        let s = try await session("basic")
        s.open(.missing)
        s.open(.page(PageRef(folder: "functional-requirements", stem: "nope")))
        #expect(s.selectedPage == nil)
        #expect(s.selectedSection == nil)
    }

    @Test func backAndForward() async throws {
        let s = try await session("basic")
        let refs = existingRefs(s)
        let a = refs[0], b = refs[1]
        s.open(.page(a))
        s.open(.page(b))
        s.back()
        #expect(s.selectedPage == a)
        s.forward()
        #expect(s.selectedPage == b)
    }

    @Test func backAtTheStartAndForwardAtTheEndDoNothing() async throws {
        let s = try await session("basic")
        let a = existingRefs(s)[0]
        s.back(); s.forward()
        #expect(s.selectedPage == nil)
        s.open(.page(a))
        s.back(); s.forward(); s.forward()
        #expect(s.selectedPage == a)
    }

    @Test func openAfterBackDropsTheForwardPath() async throws {
        let s = try await session("basic")
        let refs = existingRefs(s)
        s.open(.page(refs[0])); s.open(.page(refs[1]))
        s.back()
        s.open(.page(refs[2]))
        s.forward()
        #expect(s.selectedPage == refs[2])
        s.back()
        #expect(s.selectedPage == refs[0])
    }

    @Test func selectingASectionClearsThePageAndIsInTheHistory() async throws {
        let s = try await session("basic")
        let page = existingRefs(s)[0]
        s.open(.page(page))
        let other = try #require(s.metamodel.sections.first { $0.folders.contains("domain-terms") })
        s.select(section: other.id)
        #expect(s.selectedSection == other.id)
        #expect(s.selectedPage == nil)
        s.back()
        #expect(s.selectedSection == (try requirementsSection(s)).id)
        #expect(s.selectedPage == page)
        s.forward()
        #expect(s.selectedSection == other.id)
        #expect(s.selectedPage == nil)
    }

    @Test func selectingNothingOrTheSamePlaceAddsNoEntry() async throws {
        let s = try await session("basic")
        let a = try requirementsSection(s).id
        s.select(section: nil)
        #expect(s.selectedSection == nil)
        s.select(section: a)
        s.select(section: a)
        s.open(.page(existingRefs(s)[0]))
        s.open(.page(existingRefs(s)[0]))
        s.back()
        #expect(s.selectedSection == a && s.selectedPage == nil)
        s.back()
        #expect(s.selectedSection == a && s.selectedPage == nil)
    }

    @Test func historyKeepsTheLast100Places() async throws {
        let s = try await session("basic")
        let sections = s.metamodel.sections.map(\.id)
        for i in 0..<150 { s.select(section: sections[i % sections.count]) }
        var steps = 0
        while steps < 99 { s.back(); steps += 1 }
        #expect(steps == 99)
        let oldest = s.selectedSection
        s.back()
        #expect(s.selectedSection == oldest)
        #expect(oldest == sections[50 % sections.count])
    }

    @Test func metamodelAndSourceTargetsDoNothing() async throws {
        let s = try await session("basic")
        s.open(.metamodel("whatever"))
        s.open(.source("SRC-001"))
        s.open(.anchor("MADR"))
        #expect(s.selectedSection == nil && s.selectedPage == nil)
    }

    @Test func titleAndSubtitle() async throws {
        let copy = try Fixture.tempCopy("basic")
        try "system_name: Library\n".write(
            to: copy.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        #expect(s.title == "Library")
        #expect(s.subtitle == nil)
        let section = try requirementsSection(s)
        s.selectedSection = section.id
        #expect(s.subtitle == "\(section.title) · 6")
        s.agreedOnly = true
        #expect(s.subtitle == "\(section.title) · 5")
    }

    @Test func issueCountOpensTheIssueSectionFilteredToTheSection() async throws {
        let s = try await session("tailored")
        let from = try requirementsSection(s)
        s.showIssues(of: from.id)
        #expect(s.selectedSection == s.metamodel.issueSection?.id)
        #expect(s.issueFilter == from.id)
        s.selectedSection = from.id
        s.showIssues(of: from.id)
        #expect(s.issueFilter == from.id)
    }

    @Test func orientationShowsTheVision() async throws {
        let s = try await session("basic")
        let orientation = try #require(s.orientation)
        #expect(orientation.title == "A Library That Lends Effortlessly")
        #expect(orientation.text.hasPrefix("For library members"))
        #expect(!orientation.text.contains("\n"))
    }

    @Test func theVisionIsOnlySearchedInTypesThatListTheStereotype() async throws {
        let copy = try Fixture.tempCopy("basic")
        let file = copy.appending(path: "_system/metamodel/types/type-goal.md")
        let text = try String(contentsOf: file, encoding: .utf8)
        try text.replacingOccurrences(of: "stereotypes: [vision, objective]", with: "stereotypes: [objective]")
            .write(to: file, atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        #expect(s.orientation == nil)
    }

    @Test func readingLeavesTheWikiUnchanged() async throws {
        let copy = try Fixture.tempCopy("search")
        let root = try Preflight.open(copy)
        let s = await WikiSession.open(root)
        assertUnchanged(copy) {
            s.agreedOnly = true
            _ = s.sidebar
            _ = s.orientation
            if let ref = s.store.pages(in: "functional-requirements").first?.ref { s.open(.page(ref)) }
        }
    }

    @Test func syncInitGivesTheSameSidebarAsOpen() async throws {
        let root = try Preflight.open(Fixture.url("basic"))
        let sync = WikiSession(root: root)
        let async = await WikiSession.open(root)
        #expect(sync.sidebar.map { $0.rows.map(\.count) } == async.sidebar.map { $0.rows.map(\.count) })
    }
}

@MainActor @Suite struct OpeningTests {
    @Test func preflightFailureNamesTheParts() async throws {
        let copy = try Fixture.tempCopy("basic")
        try FileManager.default.removeItem(at: copy.appending(path: "_system/anchors"))
        let opened = await OpenedWiki.open(copy)
        guard case .failed(let failure) = opened else { Issue.record("expected a failure"); return }
        #expect(failure.missing == ["_system/anchors"])
        #expect(failure.folder == copy)
    }

    @Test func aGoodFolderOpensASession() async throws {
        let opened = await OpenedWiki.open(Fixture.url("basic"))
        guard case .session(let s) = opened else { Issue.record("expected a session"); return }
        #expect(s.title == "basic fixture")
    }
}
