import SwiftUI
import Systems42UI

// The menu bar. The rules (when a command is enabled, what it does) are in `MenuRules` in Systems42UI,
// where tests reach them without a window. The Search, Metamodel and Method commands use things that
// stay inside Systems42UI, so they stay there: SearchCommands, MetamodelCommands, MethodCommands.

private extension View {
    func shortcut(_ shortcut: Shortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

/// File > Open Folder and Open Recent. Close is the system's.
struct OpenCommands: Commands {
    let recent: RecentFolders
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                if let url = FolderChooser.choose() { openWindow.openWiki(url) }
            }
            .shortcut(Shortcuts.openFolder)
            Menu("Open Recent") {
                let labels = WikiFolders.labels(for: recent.urls)
                ForEach(Array(recent.urls.enumerated()), id: \.offset) { index, url in
                    Button(labels[index]) { openWindow.openWiki(url) }
                }
            }
            .disabled(recent.urls.isEmpty)
        }
    }
}

/// View > Reading View, Agreed Only, Show in List.
struct ViewCommands: Commands {
    @Bindable private var reading = ReadingPreference.shared
    @FocusedValue(\.wikiSession) private var session

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Reading View", isOn: $reading.plain)
                .shortcut(Shortcuts.readingView)
            Toggle(SessionCommand.agreedOnly.title, isOn: Binding(
                get: { session?.agreedOnly ?? false },
                set: { _ in MenuRules.perform(.agreedOnly, on: session) }))
                .shortcut(Shortcuts.agreedOnly)
                .disabled(!MenuRules.isEnabled(.agreedOnly, session: session))
            Button(SessionCommand.showInList.title) { MenuRules.perform(.showInList, on: session) }
                .shortcut(Shortcuts.showInList)
                .disabled(!MenuRules.isEnabled(.showInList, session: session))
        }
    }
}

/// Go: Back, Forward and the sections of the sidebar as Cmd-1 to Cmd-9. The titles come from the sidebar.
struct GoCommands: Commands {
    @FocusedValue(\.wikiSession) private var session

    var body: some Commands {
        CommandMenu("Go") {
            Button(SessionCommand.back.title) { MenuRules.perform(.back, on: session) }
                .shortcut(Shortcuts.back)
                .disabled(!MenuRules.isEnabled(.back, session: session))
            Button(SessionCommand.forward.title) { MenuRules.perform(.forward, on: session) }
                .shortcut(Shortcuts.forward)
                .disabled(!MenuRules.isEnabled(.forward, session: session))
            Divider()
            ForEach(MenuRules.sectionShortcuts(of: session), id: \.number) { entry in
                Button(entry.title) { MenuRules.selectSection(number: entry.number, in: session) }
                    .shortcut(Shortcuts.sections[entry.number - 1])
            }
        }
    }
}

/// Page: what the reader can do with the page that is shown. The toolbar and the context menu of the page offer the same.
struct PageCommands: Commands {
    @FocusedValue(\.wikiSession) private var session

    var body: some Commands {
        CommandMenu("Page") {
            action(.copyLink, Shortcuts.copyLink)
            action(.copyID, nil)
            Divider()
            action(.openInObsidian, Shortcuts.openInObsidian)
            action(.revealInFinder, nil)
            action(.share, nil)
        }
    }

    @ViewBuilder
    private func action(_ command: SessionCommand, _ keys: Shortcut?) -> some View {
        let button = Button(command.title) { MenuRules.perform(command, on: session) }
            .disabled(!MenuRules.isEnabled(command, session: session))
        if let keys { button.shortcut(keys) } else { button }
    }
}

/// Help > Systems42 Dashboard Help. Metamodel, The Method and Guided Tour follow from their own commands.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Systems42 Dashboard Help") { openWindow(id: HelpWindow.windowID) }
                .shortcut(Shortcuts.help)
        }
    }
}

/// The app menu's About item opens the About window for the focused wiki.
struct AboutCommands: Commands {
    @FocusedValue(\.wikiSession) private var session
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.windowTitle)") {
                AboutContext.shared.folder = session?.root.url
                openWindow(id: AboutWindowRoot.windowID)
            }
        }
    }
}
