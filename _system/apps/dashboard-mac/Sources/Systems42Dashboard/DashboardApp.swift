import AppKit
import SwiftUI
import Systems42UI

@main
struct DashboardApp: App {
    @State private var recent = RecentFolders()
    /// The folder named on the command line, read once at launch and opened once.
    @State private var launch = LaunchFolder(
        WikiFolders.fromArguments(Array(CommandLine.arguments.dropFirst()), currentDirectory: FileManager.default.currentDirectoryPath))

    init() {
        // `swift run` starts a bare executable. Make it a normal app with a window and a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        Window(AppInfo.windowTitle, id: "welcome") {
            Welcome(recent: recent, launch: launch)
        }
        WindowGroup("Wiki", for: URL.self) { $folder in
            if let folder {
                WikiWindowRoot(folder: folder) { recent.note($0) }
                    .frame(minWidth: 900, minHeight: 500)
            }
        }
        .commands {
            OpenCommands(recent: recent)
            ReadingCommands()
        }
    }
}

/// The welcome window. A folder named on the command line opens at once.
@MainActor @Observable private final class LaunchFolder {
    private var folder: URL?
    init(_ folder: URL?) { self.folder = folder }

    /// The folder once, then nil.
    func take() -> URL? {
        defer { folder = nil }
        return folder
    }
}

private struct Welcome: View {
    let recent: RecentFolders
    let launch: LaunchFolder
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WelcomeView(recent: recent.urls) { openWindow.openWiki($0) }
            .opensDroppedFolders()
            .task {
                guard let folder = launch.take() else { return }
                openWindow.openWiki(folder)
                dismissWindow(id: "welcome")
            }
    }
}

private struct OpenCommands: Commands {
    let recent: RecentFolders
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                if let url = FolderChooser.choose() { openWindow.openWiki(url) }
            }
            .keyboardShortcut("o")
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

private struct ReadingCommands: Commands {
    @Bindable private var reading = ReadingPreference.shared

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Reading View", isOn: $reading.plain)
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
