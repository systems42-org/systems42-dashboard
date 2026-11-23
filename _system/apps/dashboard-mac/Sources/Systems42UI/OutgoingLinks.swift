import AppKit
import Foundation

/// The one place where the app hands a URL to the system. There are two entries:
/// - `openFromContent` for every link found in wiki text or wiki data. It lets `http`, `https` and `mailto` out.
/// - `open` for the app's own actions (Open in Obsidian, the router). It also lets `obsidian` and `systems42` through.
///
/// The web view of the diagrams has no way out: its navigation delegate cancels every navigation after the first load.
public enum OutgoingLinks {
    /// The schemes a link in wiki content may open.
    public static let contentSchemes: Set<String> = ["http", "https", "mailto"]
    /// The schemes the app itself may open. Nothing else is opened.
    public static let allowedSchemes: Set<String> = contentSchemes.union(["obsidian", DeepLink.scheme])

    private static func scheme(of url: URL) -> String? { url.scheme?.lowercased() }

    public static func isAllowed(_ url: URL) -> Bool { scheme(of: url).map(allowedSchemes.contains) ?? false }

    /// For a link that came from wiki content. A refused URL does nothing.
    @MainActor @discardableResult
    public static func openFromContent(_ url: URL, using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        guard let scheme = scheme(of: url), contentSchemes.contains(scheme) else { return false }
        return opener(url)
    }

    /// For an action of the app. A `systems42` link stays in the app.
    @MainActor @discardableResult
    public static func open(
        _ url: URL,
        using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        router: DeepLinkRouter = .shared
    ) -> Bool {
        guard isAllowed(url) else { return false }
        if scheme(of: url) == DeepLink.scheme {
            router.handle(url)
            return true
        }
        return opener(url)
    }
}
