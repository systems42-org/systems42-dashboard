import AppKit
import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor @Suite struct OutgoingLinkTests {
    @Test func theAllowListIsTheFiveSchemes() {
        #expect(OutgoingLinks.allowedSchemes == ["http", "https", "mailto", "obsidian", "systems42"])
    }

    @Test func otherSchemesNeverReachTheSystem() {
        var opened: [URL] = []
        for text in ["file:///etc/passwd", "javascript:alert(1)", "ftp://x/y", "x-apple.systempreferences:com.apple.preference",
                     "smb://host/share", "tel:123", "data:text/html,hi", "vscode://x"] {
            #expect(OutgoingLinks.open(URL(string: text)!, using: { opened.append($0); return true }) == false, "\(text)")
        }
        #expect(opened.isEmpty)
    }

    @Test func allowedSchemesGoToTheOpenerInAnyCase() {
        var opened: [URL] = []
        for text in ["http://a.org", "HTTPS://a.org/x", "mailto:a@b.org", "obsidian://open?path=%2Fx"] {
            #expect(OutgoingLinks.open(URL(string: text)!, using: { opened.append($0); return true }))
        }
        #expect(opened.count == 4)
    }

    @Test func ourOwnSchemeStaysInTheApp() {
        var opened: [URL] = []
        var notices: [DeepLinkNotice] = []
        let router = DeepLinkRouter(sessions: { [] }, recent: { [] }, openWiki: { _ in }, present: { notices.append($0) }, now: { Date() })
        let handled = OutgoingLinks.open(URL(string: "systems42://Nowhere/FR-1")!, using: { opened.append($0); return true }, router: router)
        #expect(handled)
        #expect(opened.isEmpty)
        #expect(notices.count == 1)
    }

    // MARK: Obsidian

    @Test func obsidianLinkIsEncoded() throws {
        let path = "/Users/me/My Wiki/a+b&c#d%e=f/wiki/goals/GOAL-001-x.md"
        let url = try #require(PageActions.obsidianURL(forFile: URL(fileURLWithPath: path)))
        #expect(url.scheme == "obsidian")
        #expect(url.host == "open")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.queryItems?.count == 1)
        #expect(parts.queryItems?.first?.name == "path")
        #expect(parts.queryItems?.first?.value == path)
        let text = url.absoluteString
        for bad in [" ", "+", "&c", "#d", "=f"] { #expect(!text.contains(bad), "\(bad)") }
        #expect(text.hasPrefix("obsidian://open?path=%2F") || text.hasPrefix("obsidian://open?path=/"))
    }

    @Test func obsidianKeepsUmlautsAndStaysOneLine() throws {
        let path = "/Users/me/Büro\nzwei.md"
        let url = try #require(PageActions.obsidianURL(forFile: URL(fileURLWithPath: path)))
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        #expect(value == path)
        #expect(!url.absoluteString.contains("\n"))
    }

    // MARK: Page actions

    private func session() async throws -> WikiSession {
        await WikiSession.open(try Preflight.open(Fixture.url("basic")))
    }

    @Test func theActionsOfAPage() async throws {
        let s = try await session()
        let page = try #require(s.store.pages(in: "functional-requirements").first)
        let actions = try #require(PageActions(session: s, ref: page.ref))
        #expect(actions.id == page.id)
        #expect(actions.title == page.title)
        #expect(actions.link == DeepLink.url(wiki: s.title, pageID: page.id))
        #expect(actions.file.path.hasSuffix("/wiki/functional-requirements/\(page.ref.stem).md"))
        #expect(FileManager.default.fileExists(atPath: actions.file.path))
        #expect(PageActions(session: s, ref: PageRef(folder: "functional-requirements", stem: "nope")) == nil)
    }

    @Test func copyPutsTheLinkAndTheIDOnThePasteboard() async throws {
        let s = try await session()
        let page = try #require(s.store.pages(in: "functional-requirements").first)
        let actions = try #require(PageActions(session: s, ref: page.ref))
        let board = NSPasteboard(name: NSPasteboard.Name("s42-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        actions.copyLink(to: board)
        #expect(board.string(forType: .string) == actions.link.absoluteString)
        actions.copyID(to: board)
        #expect(board.string(forType: .string) == page.id)
    }

    @Test func revealNamesTheFileAndOpenInObsidianGoesThroughTheAllowList() async throws {
        let s = try await session()
        let page = try #require(s.store.pages(in: "functional-requirements").first)
        let actions = try #require(PageActions(session: s, ref: page.ref))
        var revealed: [URL] = []
        actions.revealInFinder(using: { revealed = $0 })
        #expect(revealed == [actions.file])
        var opened: [URL] = []
        actions.openInObsidian(using: { opened.append($0); return true })
        #expect(opened == [try #require(actions.obsidian)])
    }

    @Test func aFileThatIsGoneIsNotRevealed() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let page = try #require(s.store.pages(in: "functional-requirements").first)
        let actions = try #require(PageActions(session: s, ref: page.ref))
        try FileManager.default.removeItem(at: actions.file)
        var revealed: [URL] = []
        actions.revealInFinder(using: { revealed = $0 })
        #expect(revealed.isEmpty)
        #expect(actions.obsidian != nil)
    }
}
