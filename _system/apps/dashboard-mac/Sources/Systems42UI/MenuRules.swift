import Foundation
import Systems42Kit

/// The menu commands that act on the focused wiki window. `MenuRules` says when each is enabled and what it does,
/// so the rules need no window to test. The menu only calls it.
public enum SessionCommand: CaseIterable, Sendable {
    case back, forward, showInList, agreedOnly
    case copyLink, copyID, openInObsidian, revealInFinder, share

    public var title: String {
        switch self {
        case .back: "Back"
        case .forward: "Forward"
        case .showInList: "Show in List"
        case .agreedOnly: "Agreed Only"
        case .copyLink: "Copy Link"
        case .copyID: "Copy ID"
        case .openInObsidian: "Open in Obsidian"
        case .revealInFinder: "Reveal in Finder"
        case .share: "Share…"
        }
    }

    public var systemImage: String {
        switch self {
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .showInList: "list.bullet"
        case .agreedOnly: "checkmark.seal"
        case .copyLink: "link"
        case .copyID: "number"
        case .openInObsidian: "arrow.up.forward.app"
        case .revealInFinder: "folder"
        case .share: "square.and.arrow.up"
        }
    }

    /// Whether the command acts on the page that is shown.
    public var actsOnAPage: Bool {
        switch self {
        case .copyLink, .copyID, .openInObsidian, .revealInFinder, .share: true
        case .back, .forward, .showInList, .agreedOnly: false
        }
    }
}

/// A row of the sidebar that Cmd-1 to Cmd-9 reaches.
public struct SectionShortcut: Equatable, Sendable {
    public let number: Int
    public let id: WikiSection.ID
    public let title: String
}

@MainActor public enum MenuRules {
    /// The most sections a number key reaches.
    public static let mostSectionShortcuts = 9

    public static func isEnabled(_ command: SessionCommand, session: WikiSession?) -> Bool {
        guard let session else { return false }
        switch command {
        case .back: return session.canGoBack
        case .forward: return session.canGoForward
        case .showInList: return session.showsProjection
        case .agreedOnly: return true
        case .copyID, .openInObsidian, .revealInFinder:
            return pageActions(session) != nil
        case .copyLink, .share:
            return pageActions(session)?.link != nil
        }
    }

    /// Does what the command says. A command that is not enabled does nothing.
    public static func perform(_ command: SessionCommand, on session: WikiSession?) {
        guard let session, isEnabled(command, session: session) else { return }
        switch command {
        case .back: session.back()
        case .forward: session.forward()
        case .showInList: session.select(mode: ListModel.listMode)
        case .agreedOnly: session.agreedOnly.toggle()
        case .copyLink: pageActions(session)?.copyLink()
        case .copyID: pageActions(session)?.copyID()
        case .openInObsidian: pageActions(session)?.openInObsidian()
        case .revealInFinder: pageActions(session)?.revealInFinder()
        case .share: pageActions(session)?.share()
        }
    }

    private static func pageActions(_ session: WikiSession) -> PageActions? {
        session.selectedPage.flatMap { PageActions(session: session, ref: $0) }
    }

    /// The first nine rows of the sidebar in the order it shows them, with the titles it shows.
    public static func sectionShortcuts(of session: WikiSession?) -> [SectionShortcut] {
        guard let session else { return [] }
        return session.sidebar.flatMap(\.rows).prefix(mostSectionShortcuts).enumerated().map {
            SectionShortcut(number: $0.offset + 1, id: $0.element.section.id, title: $0.element.section.title)
        }
    }

    /// Cmd-<number>: the row at that place of the sidebar. A number with no row does nothing.
    public static func selectSection(number: Int, in session: WikiSession?) {
        guard let session, let shortcut = sectionShortcuts(of: session).first(where: { $0.number == number }) else { return }
        session.select(section: shortcut.id)
    }
}
