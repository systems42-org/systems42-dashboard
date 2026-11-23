import AppKit
import Foundation
import Systems42Kit

/// What the reader can do with the page that is shown: copy its link or id, open it in Obsidian or
/// Finder, share it. The app never writes to the wiki, so every action only reads the file's place.
@MainActor public struct PageActions {
    public let id: String
    public let title: String
    /// The `systems42://` link to the page. Nil when no name of the wiki makes a link the app accepts.
    public let link: URL?
    /// The page file in the wiki folder.
    public let file: URL
    private let root: WikiRoot

    /// Nil when the page does not exist in the session's wiki.
    public init?(session: WikiSession, ref: PageRef) {
        guard let page = session.store.page(ref) else { return nil }
        id = page.id
        title = page.title
        // The system name first, then the folder name. A link that would not parse back is not handed out.
        link = [session.title, session.root.url.lastPathComponent].lazy.compactMap { DeepLink.url(wiki: $0, pageID: page.id) }.first
        file = session.root.url.appending(path: "wiki").appending(path: ref.folder).appending(path: "\(ref.stem).md")
        root = session.root
    }

    /// `obsidian://open?path=<file>`, built with URL components so that spaces, `+`, `&`, `#` and `%` in a path survive.
    public static func obsidianURL(forFile file: URL) -> URL? {
        var parts = URLComponents()
        parts.scheme = "obsidian"
        parts.host = "open"
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
        guard let value = file.path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        parts.percentEncodedQueryItems = [URLQueryItem(name: "path", value: value)]
        return parts.url
    }

    public var obsidian: URL? { Self.obsidianURL(forFile: file) }

    /// Why there is no link, nil when there is one.
    public var linkProblem: String? {
        link == nil ? "Neither the name of the wiki nor the id of the page makes a link the app accepts." : nil
    }

    public func copyLink(to board: NSPasteboard = .general) {
        guard let link else { return }
        put(link.absoluteString, on: board)
    }

    public func copyID(to board: NSPasteboard = .general) { put(id, on: board) }

    private func put(_ text: String, on board: NSPasteboard) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    public func openInObsidian(using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        guard let url = obsidian else { return }
        OutgoingLinks.open(url, using: opener)
    }

    /// Shows the file in Finder. A file that is gone, or that resolves out of the wiki, is not shown.
    public func revealInFinder(using reveal: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }) {
        guard Preflight.contained("wiki/\(file.deletingLastPathComponent().lastPathComponent)/\(file.lastPathComponent)", in: root) != nil else { return }
        reveal([file])
    }

    /// Opens the system share menu for the link and the title, below the toolbar of the key window.
    public func share() {
        guard let link, let view = NSApplication.shared.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [Untrusted.clean(title, longest: 200) as NSString, link as NSURL])
        picker.show(relativeTo: NSRect(x: view.bounds.maxX - 40, y: view.bounds.maxY - 1, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
}
