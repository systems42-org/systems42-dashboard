import AppKit
import Foundation

/// The one way the app hands a URL to the system. Rendered text, page actions and the Metamodel
/// window all come here. The web view of the diagrams has no way out: its navigation delegate cancels
/// every navigation after the first load.
public enum OutgoingLinks {
    /// The schemes that may leave the app. Nothing else is opened.
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto", "obsidian", DeepLink.scheme]

    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme.map { allowedSchemes.contains($0.lowercased()) } ?? false
    }

    /// Opens the URL with the system, or does nothing and returns false. A `systems42` link stays in the app.
    @MainActor @discardableResult
    public static func open(
        _ url: URL,
        using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        router: DeepLinkRouter = .shared
    ) -> Bool {
        guard isAllowed(url) else { return false }
        if url.scheme?.lowercased() == DeepLink.scheme {
            router.handle(url)
            return true
        }
        return opener(url)
    }
}
