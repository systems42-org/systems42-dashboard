import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor
private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

@MainActor
private func row(_ session: WikiSession, folder: String) throws -> SidebarRow {
    try #require(session.sidebar.flatMap(\.rows).first { $0.section.folders.contains(folder) })
}

@MainActor @Suite struct SidebarModelTests {
    @Test func sidebarHasThreeGroupsInOrder() async throws {
        let s = try await session("basic")
        #expect(s.sidebar.map(\.area) == [.requirements, .architecture, .commons])
    }

    @Test func rowCountsMatchTheWiki() async throws {
        let s = try await session("basic")
        let requirements = try row(s, folder: "functional-requirements")
        #expect(requirements.count == 6)
        #expect(requirements.byStatus.map(\.status) == ["draft", "accepted"])
        #expect(requirements.byStatus.map(\.count) == [1, 5])
        let terms = try row(s, folder: "domain-terms")
        #expect(terms.count == 4)
        #expect(terms.byStatus.first { $0.status == "accepted" }?.count == 3)
        #expect(terms.byStatus.first { $0.status == "draft" }?.count == 1)
    }

    @Test func emptySectionShowsZero() async throws {
        let s = try await session("basic")
        let empty = try row(s, folder: "solution-strategy")
        #expect(empty.count == 0)
        #expect(empty.byStatus.isEmpty)
    }

    @Test func sectionsOfAnAreaKeepTheMetamodelOrder() async throws {
        let s = try await session("basic")
        for group in s.sidebar {
            #expect(group.rows.map(\.section.id) == s.metamodel.sections.filter { $0.area == group.area }.map(\.id))
        }
    }

    @Test func openIssuesPerSection() async throws {
        let s = try await session("search")
        let stakeholders = try row(s, folder: "stakeholders")
        #expect(stakeholders.openIssues == 1)  // ISS-002 points at no page
        for other in s.sidebar.flatMap(\.rows) where other.section.id != stakeholders.section.id {
            #expect(other.openIssues == 0, "\(other.section.id)")
        }
    }

    @Test func anIssuePointingTwiceAtASectionCountsOnce() async throws {
        let copy = try Fixture.tempCopy("search")
        let issue = copy.appending(path: "wiki/issues/ISS-001-who-holds-the-key.md")
        let text = try String(contentsOf: issue, encoding: .utf8)
        try (text + "\nAlso [[STK-020-sponsor]] and [[STK-003-requirements-engineers]].\n")
            .write(to: issue, atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        #expect(try row(s, folder: "stakeholders").openIssues == 1)
    }

    @Test func closedIssuesAreNotCounted() async throws {
        let copy = try Fixture.tempCopy("search")
        for name in ["ISS-001-who-holds-the-key", "ISS-002-guide-to-the-jedi-master-role"] {
            let file = copy.appending(path: "wiki/issues/\(name).md")
            let text = try String(contentsOf: file, encoding: .utf8)
            try text.replacingOccurrences(of: "status: open", with: "status: resolved")
                .write(to: file, atomically: true, encoding: .utf8)
        }
        let s = await WikiSession.open(try Preflight.open(copy))
        #expect(s.sidebar.flatMap(\.rows).allSatisfy { $0.openIssues == 0 })
    }

    @Test func tailoredSectionsShow() async throws {
        let s = try await session("tailored")
        let titles = s.sidebar.flatMap(\.rows).map(\.section.title)
        #expect(titles.contains("Open Points"))
        let added = try row(s, folder: "risks")
        #expect(added.count == 1)
        #expect(!titles.contains("Issues"))
    }

    @Test func agreedOnlyChangesCounts() async throws {
        let s = try await session("basic")
        s.agreedOnly = true
        let requirements = try row(s, folder: "functional-requirements")
        #expect(requirements.count == 5)
        #expect(requirements.byStatus.map(\.status) == ["accepted"])
        s.agreedOnly = false
        #expect(try row(s, folder: "functional-requirements").count == 6)
    }

    @Test func areasHaveLabelsAndColours() {
        for area in Area.allCases { #expect(!area.label.isEmpty) }
        #expect(Area.allCases.map(\.label) == ["Requirements", "Architecture", "Commons"])
    }

    @Test func statusOrderFollowsTheMetamodelLifecycle() async throws {
        let copy = try Fixture.tempCopy("basic")
        let file = copy.appending(path: "_system/metamodel/meta-metamodel.md")
        let text = try String(contentsOf: file, encoding: .utf8)
        try text.replacingOccurrences(of: "content: [draft, review, accepted, deprecated]", with: "content: [accepted, draft]")
            .write(to: file, atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        #expect(try row(s, folder: "functional-requirements").byStatus.map(\.status) == ["accepted", "draft"])
    }

    @Test func unknownLifecycleKeepsTheOrderOfAppearance() async throws {
        let copy = try Fixture.tempCopy("basic")
        try FileManager.default.removeItem(at: copy.appending(path: "_system/metamodel/meta-metamodel.md"))
        let s = await WikiSession.open(try Preflight.open(copy))
        let r = try row(s, folder: "functional-requirements")
        // FR-001 comes first in file order and is accepted.
        #expect(r.byStatus.map(\.status).first == "accepted")
        #expect(r.byStatus.count == 2)
        #expect(!r.showsMaturity)
    }

    @Test func maturityBarOnlyForTheContentLifecycle() async throws {
        let s = try await session("search")
        #expect(try row(s, folder: "functional-requirements").showsMaturity)
        #expect(try row(s, folder: "issues").showsMaturity == false)
        #expect(try row(s, folder: "issues").byStatus.map(\.status) == ["open"])
    }

    @Test func maturityShareIsAcceptedOverAll() async throws {
        let s = try await session("basic")
        #expect(try row(s, folder: "functional-requirements").agreedShare == 5.0 / 6.0)
        #expect(try row(s, folder: "solution-strategy").agreedShare == 0)
    }
}
