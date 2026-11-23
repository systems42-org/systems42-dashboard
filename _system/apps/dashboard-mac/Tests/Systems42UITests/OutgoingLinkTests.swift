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
        let router = DeepLinkRouter(sessions: { [] }, recent: { [] }, openWiki: { _ in }, activate: {}, now: { Date() })
        let handled = OutgoingLinks.open(URL(string: "systems42://Nowhere/FR-1")!, using: { opened.append($0); return true }, router: router)
        #expect(handled)
        #expect(opened.isEmpty)
        #expect(router.board.current != nil)
    }

    @Test func contentLinksOpenOnlyWebAndMail() {
        var opened: [URL] = []
        for text in ["obsidian://open?path=%2Fx", "systems42://Library/FR-1", "file:///etc/passwd", "javascript:alert(1)", "ftp://x"] {
            #expect(OutgoingLinks.openFromContent(URL(string: text)!, using: { opened.append($0); return true }) == false, "\(text)")
        }
        #expect(opened.isEmpty)
        for text in ["http://a.org", "https://a.org", "MAILTO:a@b.org"] {
            #expect(OutgoingLinks.openFromContent(URL(string: text)!, using: { opened.append($0); return true }), "\(text)")
        }
        #expect(opened.count == 3)
        #expect(OutgoingLinks.contentSchemes == ["http", "https", "mailto"])
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
        #expect(board.string(forType: .string) == actions.link?.absoluteString)
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

    // MARK: Links that would be refused

    private func hostile(title: String) throws -> (URL, WikiSession) {
        let copy = try Fixture.tempCopy("basic")
        let escaped = title.replacingOccurrences(of: "\n", with: "\\n")
        try "system_name: \"\(escaped)\"\n".write(to: copy.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
        return (copy, WikiSession(root: try Preflight.open(copy)))
    }

    @Test func aLinkWeHandOutParsesBackOrTheActionIsOff() async throws {
        let titles = [String(repeating: "漢", count: 150), "two\nlines", "x\u{202E}y", "Plain", String(repeating: "L", count: 300)]
        var sessions: [(WikiSession, URL?)] = []
        for name in Fixture.names {
            sessions.append((await WikiSession.open(try Preflight.open(Fixture.url(name))), nil))
        }
        for title in titles {
            let (copy, s) = try hostile(title: title)
            sessions.append((s, copy))
        }
        defer { for case (_, let copy?) in sessions { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) } }
        var checked = 0
        for (s, _) in sessions {
            for folder in s.store.folders() {
                for page in s.store.pages(in: folder) {
                    let actions = try #require(PageActions(session: s, ref: page.ref))
                    s.select(page: page.ref)
                    checked += 1
                    if let link = actions.link {
                        let parsed = try #require(DeepLink(link), "\(s.title) \(page.id)")
                        #expect(parsed.pageID == page.id)
                        #expect([s.title, s.root.url.lastPathComponent].contains(parsed.wiki))
                        #expect(MenuRules.isEnabled(.copyLink, session: s))
                    } else {
                        #expect(actions.linkProblem != nil)
                        #expect(!MenuRules.isEnabled(.copyLink, session: s))
                        #expect(!MenuRules.isEnabled(.share, session: s))
                    }
                }
            }
        }
        #expect(checked > 50)
    }

    @Test func aTitleThatMakesNoLinkFallsBackToTheFolderName() async throws {
        let (copy, s) = try hostile(title: String(repeating: "漢", count: 150))
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let page = try #require(s.store.pages(in: "functional-requirements").first)
        let actions = try #require(PageActions(session: s, ref: page.ref))
        let link = try #require(actions.link)
        #expect(DeepLink(link)?.wiki == "wiki-copy")
        let board = NSPasteboard(name: NSPasteboard.Name("s42-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        actions.copyLink(to: board)
        #expect(board.string(forType: .string) == link.absoluteString)
    }

    @Test func aPageFileThatIsASymlinkOutOfTheWikiIsNotRevealed() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let page = try #require(s.store.pages(in: "functional-requirements").first)
        let actions = try #require(PageActions(session: s, ref: page.ref))
        let outside = copy.deletingLastPathComponent().appending(path: "outside.md")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: actions.file)
        try FileManager.default.createSymbolicLink(at: actions.file, withDestinationURL: outside)
        var revealed: [URL] = []
        actions.revealInFinder(using: { revealed = $0 })
        #expect(revealed.isEmpty)
    }

    @Test func aPageWithAnIdTooLongForALinkHasNoLinkAndTheActionsSayWhy() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let id = String(repeating: "i", count: 300)
        let text = "---\nid: \(id)\ntype: functional-requirement\ntitle: Long\nstatus: draft\n---\n\nBody.\n"
        try text.write(to: copy.appending(path: "wiki/functional-requirements/FR-900-long.md"), atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        let ref = PageRef(folder: "functional-requirements", stem: "FR-900-long")
        s.select(page: ref)
        let actions = try #require(PageActions(session: s, ref: ref))
        #expect(actions.link == nil)
        #expect(actions.linkProblem != nil)
        #expect(!MenuRules.isEnabled(.copyLink, session: s))
        #expect(!MenuRules.isEnabled(.share, session: s))
        #expect(MenuRules.isEnabled(.copyID, session: s))
    }
}
