import AppKit
import Foundation
import Observation
import Systems42Kit

/// Text that came from a link or a wiki file, made fit for a message. It never shows more than
/// `longestShown` characters and no control, format or separator character.
enum Untrusted {
    static let longestShown = 40

    /// Control (C0, C1, DEL), format (bidi overrides, zero-width marks) and line or paragraph separators.
    static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: true
        default: false
        }
    }

    static func hasUnsafe(_ text: String) -> Bool { text.unicodeScalars.contains(where: isUnsafe) }

    /// The text without unsafe characters, cut to `longest` characters with an ellipsis.
    static func clean(_ text: String, longest: Int = longestShown) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !isUnsafe($0) })
        let plain = String(scalars)
        return plain.count > longest ? String(plain.prefix(longest)) + "…" : plain
    }

    /// `"text"` in straight quotes, so a sentence inside it reads as a quotation.
    static func quoted(_ text: String) -> String { "\"\(clean(text))\"" }

    /// A path with the home folder written as `~`.
    static func path(_ url: URL) -> String { clean((url.path as NSString).abbreviatingWithTildeInPath, longest: 60) }
}

/// A link to a page from outside the app: `systems42://<wiki>/<page id>`.
///
/// Any web page or document can open such a link, so it carries a name and an id and nothing else.
/// It never names a path, a folder or an action. The router looks the wiki up among the wikis that
/// are open or recent, and the page by id. The form differs from the internal link of `LinkAction`
/// (`systems42://page?folder=...`): that one always has a query, this one never has.
public struct DeepLink: Equatable, Sendable {
    public static let scheme = "systems42"
    /// The longest URL taken, in bytes.
    public static let longestURL = 1024
    /// The longest wiki name and page id taken, in characters after decoding.
    public static let longestPart = 200

    /// The system name or the folder name of the wiki.
    public let wiki: String
    public let pageID: String?

    init(wiki: String, pageID: String?) {
        self.wiki = wiki
        self.pageID = pageID
    }

    /// Nil unless the URL has this form exactly: scheme, a name, optionally one id. No query, no
    /// fragment, no further segment. Each part is decoded once.
    public init?(_ url: URL) {
        let text = url.absoluteString
        let prefix = Self.scheme + "://"
        guard text.utf8.count <= Self.longestURL, text.lowercased().hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        guard !rest.contains("?"), !rest.contains("#") else { return nil }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let wiki = Self.decode(parts[0]) else { return nil }
        self.wiki = wiki
        if parts.count == 2, !parts[1].isEmpty {
            guard let id = Self.decode(parts[1]) else { return nil }
            pageID = id
        } else {
            pageID = nil
        }
    }

    /// The link to a page, or nil when the app would refuse it: a part too long, blank, or holding
    /// an unsafe character. A link this returns parses back to the same wiki and page.
    public static func url(wiki: String, pageID: String) -> URL? {
        guard let url = URL(string: "\(scheme)://\(encode(wiki))/\(encode(pageID))"),
              DeepLink(url) == DeepLink(wiki: wiki, pageID: pageID) else { return nil }
        return url
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// One percent-decoding. Nil for a bad escape, a blank or too long result, or any control (C0, C1),
    /// format (bidi, zero-width) or line or paragraph separator character.
    private static func decode(_ part: Substring) -> String? {
        guard let text = String(part).removingPercentEncoding, text.count <= longestPart,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !Untrusted.hasUnsafe(text) else { return nil }
        return text
    }
}

/// What the app tells the reader when it cannot do what a link asks, and the one thing it offers to do.
public struct DeepLinkNotice {
    public struct Button {
        public let title: String
        public let run: @MainActor () -> Void
    }

    public let text: String
    public let button: Button?
    /// The wiki the button would open. The notice goes away when that wiki opens by any means.
    let waitingFor: URL?
    let id = UUID()

    init(text: String, button: Button? = nil, waitingFor: URL? = nil) {
        self.text = text
        self.button = button
        self.waitingFor = waitingFor
    }
}

/// The one notice on screen. A window shows it as a banner, and VoiceOver is told once when it is set.
/// While one shows, links are dropped. A notice without a button goes away after `lifetime`. One with a
/// button stays until the reader dismisses it or the wiki it offers has opened.
@MainActor @Observable public final class NoticeBoard {
    /// How long a notice without a button stays.
    public static let lifetime: TimeInterval = 15

    /// The kinds of window that may show the banner.
    public enum Window { case wiki, welcome }

    public private(set) var current: DeepLinkNotice?
    @ObservationIgnored private var shownAt = Date.distantPast
    /// Speaks a new notice. Tests replace it.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { NoticeBoard.speak($0) }

    func show(_ notice: DeepLinkNotice, at moment: Date) {
        current = notice
        shownAt = moment
        announce(notice.text)
    }

    public func dismiss() { current = nil }

    /// Removes a notice without a button once its time is up.
    public func expireIfDue(at moment: Date) {
        guard let current, current.button == nil, moment.timeIntervalSince(shownAt) >= Self.lifetime else { return }
        self.current = nil
    }

    /// Removes the notice that offers to open this folder.
    func dismissWaiting(for folder: URL) {
        guard let waiting = current?.waitingFor, WikiFolders.standardized(waiting) == WikiFolders.standardized(folder) else { return }
        current = nil
    }

    /// Only the frontmost wiki window shows the banner. The Welcome window shows it while no wiki window is open.
    public static func isVisible(in window: Window, isKey: Bool, wikiWindowsOpen: Bool) -> Bool {
        switch window {
        case .wiki: isKey
        case .welcome: !wikiWindowsOpen
        }
    }

    private static func speak(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// Finds the wiki and the page a link names. It selects a page, or tells the reader why not. It opens a
/// wiki only when the reader presses the button of the message. A name that fits two wikis picks none.
///
/// Limits against a flood of links: an identical link within `sameEvent` counts once, a link that arrives
/// while a notice shows is dropped, and at most `handledPerInterval` links are handled per `interval`. The
/// rest are dropped, and one fixed line says so once per interval. The app comes to the front once per handled link.
@MainActor public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    static let sameEvent: TimeInterval = 1
    static let handledPerInterval = 3
    static let interval: TimeInterval = 10
    /// The one line shown when links were dropped because of the limit. It holds no link text.
    static let tooManyLinks = "Too many links arrived. Some were ignored."
    /// How long the reader has to finish opening a wiki after pressing the button.
    static let pendingLifetime: TimeInterval = 30

    public let board = NoticeBoard()
    var sessions: @MainActor () -> [WikiSession]
    var recent: @MainActor () -> [URL]
    var openWiki: @MainActor (URL) -> Void
    var activate: @MainActor () -> Void
    var now: @MainActor () -> Date

    private var pending: (folder: URL, pageID: String?, since: Date)?
    private var last: (url: URL, at: Date)?
    private var handled: [Date] = []
    private var limitNoticeAt: Date?
    private(set) var nameReads = 0
    private var names: [URL: (modified: Date?, name: String)] = [:]

    init(
        sessions: @escaping @MainActor () -> [WikiSession] = { OpenSessions.shared.all() },
        recent: @escaping @MainActor () -> [URL] = { [] },
        openWiki: @escaping @MainActor (URL) -> Void = { _ in },
        activate: @escaping @MainActor () -> Void = { NSApplication.shared.activate() },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.sessions = sessions
        self.recent = recent
        self.openWiki = openWiki
        self.activate = activate
        self.now = now
    }

    /// The app tells the router which wikis are recent.
    public func configure(recent: @escaping @MainActor () -> [URL]) { self.recent = recent }
    /// The app tells the router how a window opens, or comes to the front.
    public func configure(openWiki: @escaping @MainActor (URL) -> Void) { self.openWiki = openWiki }

    public func handle(_ url: URL) {
        let moment = now()
        if let last, last.url == url, moment.timeIntervalSince(last.at) < Self.sameEvent { return }
        last = (url, moment)
        board.expireIfDue(at: moment)
        guard board.current == nil else { return }
        handled.removeAll { moment.timeIntervalSince($0) >= Self.interval }
        guard handled.count < Self.handledPerInterval else {
            if limitNoticeAt.map({ moment.timeIntervalSince($0) >= Self.interval }) ?? true {
                limitNoticeAt = moment
                board.show(DeepLinkNotice(text: Self.tooManyLinks), at: moment)
            }
            return
        }
        handled.append(moment)
        pending = nil
        activate()
        guard let link = DeepLink(url) else {
            tell("This link is not a Systems42 page link.")
            return
        }
        let shown = Untrusted.quoted(link.wiki)
        var open: [URL: WikiSession] = [:]
        let matches = candidates(open: &open).filter { $0.name == link.wiki || $0.folder.lastPathComponent == link.wiki }
        guard let match = matches.first else {
            tell("No open or recent wiki is named \(shown).")
            return
        }
        guard matches.count == 1 else {
            let places = matches.prefix(3).map { Untrusted.path($0.folder) }.joined(separator: ", ")
            tell("More than one wiki is named \(shown): \(places). Nothing was opened.")
            return
        }
        if let session = open[match.folder] {
            select(link.pageID, in: session)
            return
        }
        let folder = match.folder, pageID = link.pageID
        let name = Untrusted.clean(match.name)
        board.show(DeepLinkNotice(
            text: "The wiki \"\(name)\" is not open. A link does not open it by itself.",
            button: .init(title: "Open \(name)") { [weak self] in
                guard let self else { return }
                pending = (folder, pageID, now())
                openWiki(folder)
            },
            waitingFor: folder), at: moment)
    }

    /// A wiki finished opening. A link that waited for exactly this folder selects its page now, once.
    /// Another wiki that finishes meanwhile is not the one the reader agreed to.
    public func sessionOpened(_ session: WikiSession) {
        board.dismissWaiting(for: session.root.url)
        guard let waiting = pending else { return }
        guard now().timeIntervalSince(waiting.since) < Self.pendingLifetime else {
            pending = nil
            return
        }
        guard WikiFolders.standardized(waiting.folder) == WikiFolders.standardized(session.root.url) else { return }
        pending = nil
        select(waiting.pageID, in: session)
    }

    /// A wiki could not be opened. The link that waited for it is dropped.
    public func openFailed(_ folder: URL) {
        guard let waiting = pending, WikiFolders.standardized(waiting.folder) == WikiFolders.standardized(folder) else { return }
        pending = nil
    }

    private func select(_ pageID: String?, in session: WikiSession) {
        if let pageID {
            // The id is looked up and nothing else: a path, or a stem that is no id, finds no page.
            guard let page = session.store.page(id: pageID) else {
                tell("The wiki \(Untrusted.quoted(session.title)) has no page \(Untrusted.quoted(pageID)).")
                return
            }
            session.select(page: page.ref)
        }
        // Brings the window of that folder to the front.
        openWiki(session.root.url)
    }

    private func tell(_ text: String) {
        board.show(DeepLinkNotice(text: text), at: now())
    }

    private struct Candidate {
        let name: String
        let folder: URL
    }

    /// The wikis a link may name: the open ones, then the recent ones that are wikis and not open.
    /// The name of a recent wiki is read from `wiki.yaml` once per change of that file.
    private func candidates(open: inout [URL: WikiSession]) -> [Candidate] {
        var found: [Candidate] = []
        for session in sessions() {
            let folder = WikiFolders.standardized(session.root.url)
            guard open[folder] == nil else { continue }
            open[folder] = session
            found.append(Candidate(name: session.title, folder: folder))
        }
        for url in recent() {
            let folder = WikiFolders.standardized(url)
            guard open[folder] == nil, !found.contains(where: { $0.folder == folder }),
                  let root = try? Preflight.open(folder) else { continue }
            let modified = (try? folder.appending(path: "_system/wiki.yaml").resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if names[folder]?.modified != modified || names[folder] == nil {
                nameReads += 1
                names[folder] = (modified, WikiConfig.load(root).systemName)
            }
            found.append(Candidate(name: names[folder]?.name ?? folder.lastPathComponent, folder: folder))
        }
        return found
    }
}
