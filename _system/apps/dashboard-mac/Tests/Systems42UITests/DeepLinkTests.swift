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
        let url = try #require(DeepLink.url(wiki: "Library", pageID: "FR-002"))
        #expect(DeepLink(url) == DeepLink(wiki: "Library", pageID: "FR-002"))
    }

    @Test func aNameWithASpaceAndAnUmlautSurvives() throws {
        for name in ["Meine Bücherei", "a/b", "q?x#y", "100%", "a+b&c=d", "日本"] {
            let url = try #require(DeepLink.url(wiki: name, pageID: "GOAL 1/é"), "\(name)")
            let link = try #require(DeepLink(url), "\(name)")
            #expect(link.wiki == name)
            #expect(link.pageID == "GOAL 1/é")
        }
    }

    @Test func theLinkIsPlainAscii() {
        let text = DeepLink.url(wiki: "Meine Bücherei", pageID: "FR-1")?.absoluteString
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

    private func link(_ wiki: String, _ id: String) -> URL {
        DeepLink.url(wiki: wiki, pageID: id) ?? URL(string: "systems42://")!
    }

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @MainActor private struct Rig {
        let router: DeepLinkRouter
        let opened: Box<[URL]>
        let activations: Box<Int>
        var notice: DeepLinkNotice? { router.board.current }
    }

    private func rig(sessions: [WikiSession], recent: [URL] = [], now: @escaping @MainActor () -> Date = { Date() }) -> Rig {
        let opened = Box<[URL]>([])
        let activations = Box(0)
        let router = DeepLinkRouter(sessions: { sessions }, recent: { recent }, openWiki: { opened.value.append($0) },
                                    activate: { activations.value += 1 }, now: now)
        return Rig(router: router, opened: opened, activations: activations)
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
        r.router.handle(link(s.title, page.id))
        #expect(s.selectedPage == page.ref)
        #expect(r.notice == nil)
        #expect(r.opened.value == [s.root.url])
    }

    @Test func theFolderNameFindsTheWikiToo() async throws {
        let s = try await session("basic")
        let page = try firstPage(s)
        let r = rig(sessions: [s])
        r.router.handle(link(s.root.url.lastPathComponent, page.id))
        #expect(s.selectedPage == page.ref)
    }

    @Test func unknownPageChangesNothing() async throws {
        let s = try await session("basic")
        let before = try firstPage(s)
        s.select(page: before.ref)
        let r = rig(sessions: [s])
        r.router.handle(link(s.title, "FR-999-nothing"))
        #expect(s.selectedPage == before.ref)
        #expect(r.notice != nil)
        #expect(r.notice?.button == nil)
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
        #expect(r.notice != nil)
    }

    @Test func anUnknownWikiShowsAMessageAndChangesNothing() async throws {
        let s = try await session("basic")
        let r = rig(sessions: [s])
        r.router.handle(link("No Such Wiki", "FR-1"))
        #expect(s.selectedPage == nil)
        #expect(r.notice != nil)
        #expect(r.opened.value.isEmpty)
    }

    @Test func aMalformedLinkShowsAMessage() async throws {
        let r = rig(sessions: [])
        r.router.handle(URL(string: "systems42://")!)
        #expect(r.notice != nil)
    }

    @Test func aClosedRecentWikiOffersToOpenAndDoesNotOpenByItself() async throws {
        let open = try await session("basic")
        let closed = Fixture.url("search")
        let name = WikiConfig.load(try Preflight.open(closed)).systemName
        let r = rig(sessions: [open], recent: [closed])
        r.router.handle(link(name, "FR-1"))
        #expect(r.opened.value.isEmpty)
        let notice = try #require(r.notice)
        #expect(notice.button?.title == "Open \(name)")
        notice.button?.run()
        #expect(r.opened.value == [WikiFolders.standardized(closed)])
    }

    @Test func theLinkIsKeptUntilTheOpenedWikiIsThere() async throws {
        let closed = try await session("search")
        let page = try #require(closed.store.pages(in: "functional-requirements").first)
        let r = rig(sessions: [], recent: [closed.root.url])
        r.router.handle(link(closed.title, page.id))
        r.notice?.button?.run()
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
        r.router.handle(link(plain.lastPathComponent, "FR-1"))
        #expect(r.notice?.button == nil)
        #expect(r.opened.value.isEmpty)
    }

    @Test func twoWikisWithOneNameShowAMessageAndPickNone() async throws {
        let s = try await session("basic")
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let page = try firstPage(s)
        let r = rig(sessions: [s], recent: [copy])
        r.router.handle(link(s.title, page.id))
        #expect(s.selectedPage == nil)
        #expect(r.opened.value.isEmpty)
        #expect(r.notice != nil)
        #expect(r.notice?.button == nil)
    }

    @Test func theSameLinkTwiceInOneEventActsOnce() async throws {
        let s = try await session("basic")
        let r = rig(sessions: [s], now: { Date(timeIntervalSince1970: 1000) })
        let url = link(s.title, "FR-999-nothing")
        r.router.handle(url)
        r.router.handle(url)
        #expect(r.activations.value == 1)
        #expect(r.notice != nil)
    }

    // MARK: Floods

    @Test func aLinkWhileANoticeShowsIsDroppedAndAfterTheNoticeItActs() async throws {
        let s = try await session("basic")
        let page = try firstPage(s)
        let r = rig(sessions: [s], now: { Date(timeIntervalSince1970: 1000) })
        r.router.handle(link(s.title, "FR-999-nothing"))
        let first = r.notice?.text
        r.router.handle(link(s.title, page.id))
        r.router.handle(link("Nowhere", "x"))
        #expect(s.selectedPage == nil)
        #expect(r.notice?.text == first)
        #expect(r.activations.value == 1)
        r.router.board.dismiss()
        r.router.handle(link(s.title, page.id))
        #expect(s.selectedPage == page.ref)
    }

    @Test func aThousandDistinctLinksGiveOneNoticeAndFewHandled() async throws {
        let s = try await session("basic")
        let r = rig(sessions: [s], now: { Date(timeIntervalSince1970: 1000) })
        var shown = Set<String>()
        for i in 0..<1000 {
            r.router.handle(link(s.title, "FR-\(i)-nothing"))
            if let text = r.notice?.text { shown.insert(text) }
        }
        #expect(shown.count == 1)
        #expect(r.activations.value == 1)
    }

    @Test func aThousandLinksToPagesHandleAtMostTheLimitAndKeepTheHistoryShort() async throws {
        let s = try await session("basic")
        let ids = s.store.pages(in: "functional-requirements").map(\.id)
        #expect(ids.count >= 2)
        let r = rig(sessions: [s], now: { Date(timeIntervalSince1970: 1000) })
        for i in 0..<1000 {
            r.router.handle(link(i % 2 == 0 ? s.title : s.root.url.lastPathComponent, ids[i % ids.count]))
            r.router.board.dismiss()
        }
        #expect(r.activations.value <= DeepLinkRouter.handledPerWindow)
        #expect(s.historyCount <= DeepLinkRouter.handledPerWindow)
        #expect(r.opened.value.count <= DeepLinkRouter.handledPerWindow)
    }

    @Test func theLimitIsPerWindowOfTime() async throws {
        let s = try await session("basic")
        let ids = s.store.pages(in: "functional-requirements").map(\.id)
        let clock = Box(Date(timeIntervalSince1970: 1000))
        let r = rig(sessions: [s], now: { clock.value })
        for i in 0..<DeepLinkRouter.handledPerWindow + 2 { r.router.handle(link(s.title, ids[i % ids.count])) }
        #expect(r.activations.value == DeepLinkRouter.handledPerWindow)
        clock.value = clock.value.addingTimeInterval(DeepLinkRouter.window + 1)
        r.router.handle(link(s.title, ids[0] + "-x"))
        #expect(r.activations.value == DeepLinkRouter.handledPerWindow + 1)
    }

    // MARK: Text from a link

    @Test func partsWithControlFormatOrSeparatorCharactersAreRefused() {
        let bad = ["%00", "%0A", "%0D", "%1B", "%7F", "%C2%80", "%C2%85", "%C2%9F",   // C0, DEL, C1 including NEL
                   "%E2%80%AE", "%E2%80%AD", "%E2%81%A6", "%E2%80%8B", "%E2%80%8E", "%EF%BB%BF", "%C2%AD", // Cf: bidi, zero width, BOM, soft hyphen
                   "%E2%80%A8", "%E2%80%A9"]                                          // line and paragraph separator
        for escape in bad {
            #expect(parse("systems42://Lib\(escape)rary/FR-1") == nil, "wiki \(escape)")
            #expect(parse("systems42://Library/FR\(escape)-1") == nil, "id \(escape)")
        }
    }

    @Test func aNameFromALinkIsShownShortAndQuoted() async throws {
        let s = try await session("basic")
        let sentence = String(repeating: "Please press the button to win a prize. ", count: 5)
        let name = String(sentence.prefix(DeepLink.longestPart))
        let r = rig(sessions: [s])
        r.router.handle(link(name, "FR-1"))
        let text = try #require(r.notice?.text)
        #expect(text.hasPrefix("No open or recent wiki is named \""))
        #expect(text.contains("…\""))
        #expect(!text.contains(String(name.prefix(Untrusted.longestShown + 5))))
        #expect(text.count < 100)
    }

    @Test func aPageIdFromALinkIsShownShortToo() async throws {
        let s = try await session("basic")
        let r = rig(sessions: [s])
        r.router.handle(link(s.title, String(repeating: "x", count: 150)))
        let text = try #require(r.notice?.text)
        #expect(text.contains("…\""))
        #expect(!text.contains(String(repeating: "x", count: Untrusted.longestShown + 1)))
    }

    @Test func untrustedTextLosesUnsafeCharactersAndIsCut() {
        #expect(Untrusted.clean("a\u{202E}b\nc\u{200B}d\u{0085}e\u{2028}f") == "abcdef")
        #expect(Untrusted.clean(String(repeating: "y", count: 41)) == String(repeating: "y", count: 40) + "…")
        #expect(Untrusted.clean(String(repeating: "y", count: 40)) == String(repeating: "y", count: 40))
        #expect(Untrusted.quoted("a\nb") == "\"ab\"")
    }

    @Test func theNameOfTheOpenButtonIsBounded() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let long = String(repeating: "N", count: 120)
        try "system_name: \"\(long)\"\n".write(to: copy.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
        let r = rig(sessions: [], recent: [copy])
        r.router.handle(link(long, "FR-1"))
        let title = try #require(r.notice?.button?.title)
        #expect(title.count <= "Open ".count + Untrusted.longestShown + 1)
    }

    @Test func foldersInAMessageUseTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let inHome = home.appending(path: "s42-test-\(UUID().uuidString)")
        #expect(Untrusted.path(inHome).hasPrefix("~/"))
        #expect(!Untrusted.path(inHome).contains(home.path))
    }

    // MARK: Links we hand out

    @Test func urlIsNilWhenTheAppWouldRefuseIt() {
        #expect(DeepLink.url(wiki: String(repeating: "漢", count: 150), pageID: "FR-1") == nil)
        #expect(DeepLink.url(wiki: "a\nb", pageID: "FR-1") == nil)
        #expect(DeepLink.url(wiki: "  ", pageID: "FR-1") == nil)
        #expect(DeepLink.url(wiki: "ok", pageID: "") == nil)
        #expect(DeepLink.url(wiki: "ok", pageID: "a\u{202E}b") == nil)
        #expect(DeepLink.url(wiki: "ok", pageID: String(repeating: "i", count: 201)) == nil)
        #expect(DeepLink.url(wiki: "ok", pageID: "FR-1") != nil)
    }

    // MARK: The wiki that is opened

    @Test func aLinkWaitsForTheFolderTheReaderAgreedTo() async throws {
        let a = try await session("search")
        let b = try await session("arc42")
        let page = try #require(a.store.pages(in: "functional-requirements").first)
        let r = rig(sessions: [], recent: [a.root.url])
        r.router.handle(link(a.title, page.id))
        r.notice?.button?.run()
        r.router.sessionOpened(b)
        #expect(a.selectedPage == nil)
        #expect(b.selectedPage == nil)
        r.router.sessionOpened(a)
        #expect(a.selectedPage == page.ref)
    }

    @Test func aFailedOpenDropsTheWaitingLink() async throws {
        let a = try await session("search")
        let page = try #require(a.store.pages(in: "functional-requirements").first)
        let r = rig(sessions: [], recent: [a.root.url])
        r.router.handle(link(a.title, page.id))
        r.notice?.button?.run()
        r.router.openFailed(a.root.url)
        r.router.sessionOpened(a)
        #expect(a.selectedPage == nil)
    }

    @Test func aFailureOfAnotherFolderKeepsTheWaitingLink() async throws {
        let a = try await session("search")
        let b = try await session("arc42")
        let page = try #require(a.store.pages(in: "functional-requirements").first)
        let r = rig(sessions: [], recent: [a.root.url])
        r.router.handle(link(a.title, page.id))
        r.notice?.button?.run()
        r.router.openFailed(b.root.url)
        r.router.sessionOpened(a)
        #expect(a.selectedPage == page.ref)
    }

    @Test func aWaitingLinkExpires() async throws {
        let a = try await session("search")
        let page = try #require(a.store.pages(in: "functional-requirements").first)
        let clock = Box(Date(timeIntervalSince1970: 1000))
        let r = rig(sessions: [], recent: [a.root.url], now: { clock.value })
        r.router.handle(link(a.title, page.id))
        r.notice?.button?.run()
        clock.value = clock.value.addingTimeInterval(DeepLinkRouter.pendingLifetime + 1)
        r.router.sessionOpened(a)
        #expect(a.selectedPage == nil)
    }

    // MARK: Names of recent wikis

    @Test func theNameOfARecentWikiIsReadOncePerChangeOfItsFile() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let file = copy.appending(path: "_system/wiki.yaml")
        try "system_name: \"First\"\n".write(to: file, atomically: true, encoding: .utf8)
        let clock = Box(Date(timeIntervalSince1970: 1000))
        let r = rig(sessions: [], recent: [copy], now: { clock.value })
        r.router.handle(link("First", "x"))
        #expect(r.notice?.button != nil)
        r.router.board.dismiss()
        clock.value = clock.value.addingTimeInterval(DeepLinkRouter.window + 1)
        r.router.handle(link("First", "y"))
        #expect(r.router.nameReads == 1)
        r.router.board.dismiss()
        try "system_name: \"Second\"\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(500)], ofItemAtPath: file.path)
        clock.value = clock.value.addingTimeInterval(DeepLinkRouter.window + 1)
        r.router.handle(link("Second", "x"))
        #expect(r.router.nameReads == 2)
        #expect(r.notice?.button?.title == "Open Second")
    }
}
