import AppKit
import Foundation
import Systems42Kit

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

    public static func url(wiki: String, pageID: String) -> URL {
        let text = "\(scheme)://\(encode(wiki))/\(encode(pageID))"
        return URL(string: text) ?? URL(string: "\(scheme):")!
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// One percent-decoding. Nil for a bad escape, an empty or blank result, a control character or a result too long.
    private static func decode(_ part: Substring) -> String? {
        guard let text = String(part).removingPercentEncoding, text.count <= longestPart,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
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
}

/// Finds the wiki and the page a link names. It selects a page, or tells the reader why not. It opens a
/// wiki only when the reader presses the button of the message. A name that fits two wikis picks none.
@MainActor public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    /// How long an identical link counts as one event. Several windows may each be told of one click.
    static let sameEvent: TimeInterval = 1

    var sessions: @MainActor () -> [WikiSession]
    var recent: @MainActor () -> [URL]
    var openWiki: @MainActor (URL) -> Void
    var present: @MainActor (DeepLinkNotice) -> Void
    var now: @MainActor () -> Date

    private var pending: (folder: URL, pageID: String?)?
    private var last: (url: URL, at: Date)?

    init(
        sessions: @escaping @MainActor () -> [WikiSession] = { OpenSessions.shared.all() },
        recent: @escaping @MainActor () -> [URL] = { [] },
        openWiki: @escaping @MainActor (URL) -> Void = { _ in },
        present: @escaping @MainActor (DeepLinkNotice) -> Void = { DeepLinkRouter.show($0) },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.sessions = sessions
        self.recent = recent
        self.openWiki = openWiki
        self.present = present
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
        pending = nil
        guard let link = DeepLink(url) else {
            tell("This link is not a Systems42 page link.")
            return
        }
        var open: [URL: WikiSession] = [:]
        let matches = candidates(open: &open).filter { $0.name == link.wiki || $0.folder.lastPathComponent == link.wiki }
        guard let match = matches.first else {
            tell("No open or recent wiki is named \u{201C}\(link.wiki)\u{201D}.")
            return
        }
        guard matches.count == 1 else {
            let places = matches.map { $0.folder.path }.joined(separator: ", ")
            tell("More than one wiki is named \u{201C}\(link.wiki)\u{201D}: \(places). Nothing was opened.")
            return
        }
        if let session = open[match.folder] {
            select(link.pageID, in: session)
            return
        }
        let folder = match.folder, pageID = link.pageID
        present(DeepLinkNotice(
            text: "The wiki \u{201C}\(match.name)\u{201D} is not open. A link does not open it by itself.",
            button: .init(title: "Open \(match.name)") { [weak self] in
                self?.pending = (folder, pageID)
                self?.openWiki(folder)
            }))
    }

    /// A wiki finished opening. A link that waited for it selects its page now, once.
    public func sessionOpened(_ session: WikiSession) {
        guard let waiting = pending, WikiFolders.standardized(waiting.folder) == WikiFolders.standardized(session.root.url) else { return }
        pending = nil
        select(waiting.pageID, in: session)
    }

    private func select(_ pageID: String?, in session: WikiSession) {
        if let pageID {
            // The id is looked up and nothing else: a path, or a stem that is no id, finds no page.
            guard let page = session.store.page(id: pageID) else {
                tell("The wiki \u{201C}\(session.title)\u{201D} has no page \u{201C}\(pageID)\u{201D}.")
                return
            }
            session.select(page: page.ref)
        }
        // Brings the window of that folder to the front.
        openWiki(session.root.url)
    }

    private func tell(_ text: String) {
        present(DeepLinkNotice(text: text, button: nil))
    }

    private struct Candidate {
        let name: String
        let folder: URL
    }

    /// The wikis a link may name: the open ones, then the recent ones that are wikis and not open.
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
            found.append(Candidate(name: WikiConfig.load(root).systemName, folder: folder))
        }
        return found
    }

    /// The window of a message: a modal alert, so it needs no window of its own to hang on.
    private static func show(_ notice: DeepLinkNotice) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = notice.text
            if let button = notice.button {
                alert.addButton(withTitle: button.title)
                alert.addButton(withTitle: "Cancel")
            } else {
                alert.addButton(withTitle: "OK")
            }
            NSApplication.shared.activate()
            if alert.runModal() == .alertFirstButtonReturn { notice.button?.run() }
        }
    }
}
