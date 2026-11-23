import SwiftUI

/// The page actions as buttons. The toolbar menu, the context menu of the page and the Page menu all show these.
struct PageActionButtons: View {
    let session: WikiSession

    private static let order: [SessionCommand] = [.copyLink, .copyID, .openInObsidian, .revealInFinder, .share]

    /// Why a link command is off while a page is shown.
    private static func reason(_ command: SessionCommand, _ session: WikiSession) -> String? {
        guard command == .copyLink || command == .share, let ref = session.selectedPage else { return nil }
        return PageActions(session: session, ref: ref)?.linkProblem
    }

    var body: some View {
        ForEach(Self.order, id: \.self) { command in
            Button(command.title, systemImage: command.systemImage) { MenuRules.perform(command, on: session) }
                .disabled(!MenuRules.isEnabled(command, session: session))
                .help(Self.reason(command, session) ?? "")
        }
    }
}

/// The toolbar item of a wiki window: the actions of the page that is shown.
struct PageActionsMenu: View {
    let session: WikiSession

    var body: some View {
        Menu {
            PageActionButtons(session: session)
        } label: {
            Label("Page Actions", systemImage: "ellipsis.circle")
        }
        .help("Copy a link to the page, open it in Obsidian or Finder, share it")
        .disabled(session.selectedPage == nil)
    }
}
