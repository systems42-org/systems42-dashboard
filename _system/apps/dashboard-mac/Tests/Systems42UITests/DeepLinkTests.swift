import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor @Suite struct DeepLinkTests {
    // MARK: The form

    /// A text that is no URL at all is rejected too.
    private func parse(_ text: String) -> DeepLink? { URL(string: text).flatMap { DeepLink($0) } }

    @Test func deepLinkRoundTrip() throws {
        let link = try #require(DeepLink(DeepLink.url(wiki: "Library", pageID: "FR-002")))
        #expect(link == DeepLink(wiki: "Library", pageID: "FR-002"))
    }

    @Test func aNameWithASpaceAndAnUmlautSurvives() throws {
        for name in ["Meine Bücherei", "a/b", "q?x#y", "100%", "a+b&c=d", "日本"] {
            let link = try #require(DeepLink(DeepLink.url(wiki: name, pageID: "GOAL 1/é")), "\(name)")
            #expect(link.wiki == name)
            #expect(link.pageID == "GOAL 1/é")
        }
    }

    @Test func theLinkIsPlainAscii() {
        let text = DeepLink.url(wiki: "Meine Bücherei", pageID: "FR-1").absoluteString
        #expect(text == "systems42://Meine%20B%C3%BCcherei/FR-1")
    }

    @Test func deepLinkRejectsOtherSchemes() {
        for text in ["https://x/y", "systems42://", "systems42:///FR-002", "systems42:", "file:///etc/passwd", "systems43://Library/FR-1"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func aWikiAloneIsALink() throws {
        let link = try #require(DeepLink(URL(string: "systems42://Library")!))
        #expect(link.pageID == nil)
        #expect(DeepLink(URL(string: "systems42://Library/")!)?.pageID == nil)
    }

    @Test func queriesFragmentsAndExtraSegmentsAreRefused() {
        for text in ["systems42://Library/FR-1?x=1", "systems42://Library/FR-1#top", "systems42://Library/FR-1/more",
                     "systems42://Library?folder=a&stem=b"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func badEscapesAndControlCharactersAreRefused() {
        for text in ["systems42://Lib%zz/FR-1", "systems42://Library/%00", "systems42://%0A/FR-1", "systems42://%20/FR-1", "systems42://Library/%C3"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func percentDecodingHappensOnce() throws {
        let link = try #require(DeepLink(URL(string: "systems42://Library/%2541")!))
        #expect(link.pageID == "%41")
    }

    @Test func lengthsAreBounded() {
        let ok = String(repeating: "a", count: DeepLink.longestPart)
        #expect(parse("systems42://\(ok)/\(ok)") != nil)
        let long = String(repeating: "a", count: DeepLink.longestPart + 1)
        #expect(parse("systems42://\(long)/x") == nil)
        #expect(parse("systems42://w/\(long)") == nil)
        let huge = String(repeating: "a", count: DeepLink.longestURL)
        #expect(parse("systems42://w/\(huge)") == nil)
    }

    @Test func theInternalFormAndTheOutsideFormCannotBeTakenForEachOther() throws {
        let internalURL = LinkAction.page(PageRef(folder: "goals", stem: "GOAL-1")).url
        #expect(DeepLink(internalURL) == nil)
        for text in ["systems42://Library/FR-1", "systems42://page", "systems42://page/FR-1", "systems42://anchor/MADR", "systems42://Library"] {
            #expect(LinkAction(url: URL(string: text)!) == nil, "\(text)")
        }
    }

    // MARK: The router

    private struct Rig {
        let router: DeepLinkRouter
        let notices: Box<[DeepLinkNotice]>
        let opened: Box<[URL]>
    }

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private func rig(sessions: [WikiSession], recent: [URL] = [], now: @escaping @MainActor () -> Date = { Date() }) -> Rig {
        let notices = Box<[DeepLinkNotice]>([])
        let opened = Box<[URL]>([])
        let router = DeepLinkRouter(sessions: { sessions }, recent: { recent }, openWiki: { opened.value.append($0) },
                                    present: { notices.value.append($0) }, now: now)
        return Rig(router: router, notices: notices, opened: opened)
    }

    private func session(_ fixture: String) async throws -> WikiSession {
        await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
    }

    private func firstPage(_ s: WikiSession) throws -> Page {
        try #require(s.store.pages(in: "functional-requirements").first)
    }

    @Test func aLinkSelectsThePageOfAnOpenWiki() async throws {
        let s = try await session("basic")
        let page = try firstPage(s)
        let r = rig(sessions: [s])
        r.router.handle(DeepLink.url(wiki: s.title, pageID: page.id))
        #expect(s.selectedPage == page.ref)
        #expect(r.notices.value.isEmpty)
        #expect(r.opened.value == [s.root.url])
    }

    @Test func theFolderNameFindsTheWikiToo() async throws {
        let s = try await session("basic")
        let page = try firstPage(s)
        let r = rig(sessions: [s])
        r.router.handle(DeepLink.url(wiki: s.root.url.lastPathComponent, pageID: page.id))
        #expect(s.selectedPage == page.ref)
    }

    @Test func unknownPageChangesNothing() async throws {
        let s = try await session("basic")
        let before = try firstPage(s)
        s.select(page: before.ref)
        let r = rig(sessions: [s])
        r.router.handle(DeepLink.url(wiki: s.title, pageID: "FR-999-nothing"))
        #expect(s.selectedPage == before.ref)
        #expect(r.notices.value.count == 1)
        #expect(r.notices.value.first?.button == nil)
        #expect(r.opened.value.isEmpty)
    }

    @Test func deepLinkCannotNameAPath() async throws {
        let s = try await session("basic")
        let r = rig(sessions: [s])
        let url = URL(string: "systems42://\(s.title.replacingOccurrences(of: " ", with: "%20"))/..%2F..%2Fetc%2Fpasswd")!
        let link = try #require(DeepLink(url))
        #expect(link.pageID == "../../etc/passwd")
        r.router.handle(url)
        #expect(s.selectedPage == nil)
        #expect(s.selectedSection == nil)
        #expect(r.notices.value.count == 1)
    }

    @Test func anUnknownWikiShowsAMessageAndChangesNothing() async throws {
        let s = try await session("basic")
        let r = rig(sessions: [s])
        r.router.handle(DeepLink.url(wiki: "No Such Wiki", pageID: "FR-1"))
        #expect(s.selectedPage == nil)
        #expect(r.notices.value.count == 1)
        #expect(r.opened.value.isEmpty)
    }

    @Test func aMalformedLinkShowsAMessage() async throws {
        let r = rig(sessions: [])
        r.router.handle(URL(string: "systems42://")!)
        #expect(r.notices.value.count == 1)
    }

    @Test func aClosedRecentWikiOffersToOpenAndDoesNotOpenByItself() async throws {
        let open = try await session("basic")
        let closed = Fixture.url("search")
        let name = WikiConfig.load(try Preflight.open(closed)).systemName
        let r = rig(sessions: [open], recent: [closed])
        r.router.handle(DeepLink.url(wiki: name, pageID: "FR-1"))
        #expect(r.opened.value.isEmpty)
        let notice = try #require(r.notices.value.first)
        #expect(notice.button?.title == "Open \(name)")
        notice.button?.run()
        #expect(r.opened.value == [WikiFolders.standardized(closed)])
    }

    @Test func theLinkIsKeptUntilTheOpenedWikiIsThere() async throws {
        let closed = try await session("search")
        let page = try #require(closed.store.pages(in: "functional-requirements").first)
        let r = rig(sessions: [], recent: [closed.root.url])
        r.router.handle(DeepLink.url(wiki: closed.title, pageID: page.id))
        r.notices.value.first?.button?.run()
        #expect(closed.selectedPage == nil)
        r.router.sessionOpened(closed)
        #expect(closed.selectedPage == page.ref)
        // Once only.
        closed.select(section: try #require(closed.metamodel.sections.first).id)
        r.router.sessionOpened(closed)
        #expect(closed.selectedPage == nil)
    }

    @Test func aWikiThatIsNotAWikiIsNotOffered() throws {
        let plain = FileManager.default.temporaryDirectory.appending(path: "s42-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        let r = rig(sessions: [], recent: [plain])
        r.router.handle(DeepLink.url(wiki: plain.lastPathComponent, pageID: "FR-1"))
        #expect(r.notices.value.first?.button == nil)
        #expect(r.opened.value.isEmpty)
    }

    @Test func twoWikisWithOneNameShowAMessageAndPickNone() async throws {
        let s = try await session("basic")
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let page = try firstPage(s)
        let r = rig(sessions: [s], recent: [copy])
        r.router.handle(DeepLink.url(wiki: s.title, pageID: page.id))
        #expect(s.selectedPage == nil)
        #expect(r.opened.value.isEmpty)
        #expect(r.notices.value.count == 1)
        #expect(r.notices.value.first?.button == nil)
    }

    @Test func theSameLinkTwiceInOneEventActsOnce() async throws {
        let s = try await session("basic")
        let page = try firstPage(s)
        let r = rig(sessions: [s], now: { Date(timeIntervalSince1970: 1000) })
        let url = DeepLink.url(wiki: s.title, pageID: "FR-999-nothing")
        r.router.handle(url)
        r.router.handle(url)
        #expect(r.notices.value.count == 1)
        r.router.handle(DeepLink.url(wiki: s.title, pageID: page.id))
        #expect(s.selectedPage == page.ref)
    }

    @Test func aLinkLaterActsAgain() async throws {
        let s = try await session("basic")
        let clock = Box(Date(timeIntervalSince1970: 1000))
        let r = rig(sessions: [s], now: { clock.value })
        let url = DeepLink.url(wiki: s.title, pageID: "FR-999-nothing")
        r.router.handle(url)
        clock.value = Date(timeIntervalSince1970: 2000)
        r.router.handle(url)
        #expect(r.notices.value.count == 2)
    }
}
