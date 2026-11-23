import SwiftUI

/// The page actions as buttons. The toolbar menu, the context menu of the page and the Page menu all show these.
struct PageActionButtons: View {
    let session: WikiSession

    private static let order: [SessionCommand] = [.copyLink, .copyID, .openInObsidian, .revealInFinder, .share]

    var body: some View {
        ForEach(Self.order, id: \.self) { command in
            Button(command.title, systemImage: command.systemImage) { MenuRules.perform(command, on: session) }
                .disabled(!MenuRules.isEnabled(command, session: session))
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
