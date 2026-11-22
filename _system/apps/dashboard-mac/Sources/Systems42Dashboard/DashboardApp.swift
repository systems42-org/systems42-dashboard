import AppKit
import SwiftUI
import Systems42UI

@main
struct DashboardApp: App {
    @State private var recent = RecentFolders()

    init() {
        // `swift run` starts a bare executable. Make it a normal app with a window and a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        Window(AppInfo.windowTitle, id: "welcome") {
            Welcome(recent: recent)
        }
        WindowGroup("Wiki", for: URL.self) { $folder in
            if let folder {
                WikiWindowRoot(folder: folder) { recent.note($0) }
                    .frame(minWidth: 900, minHeight: 500)
            }
        }
        .commands { OpenCommands(recent: recent) }
    }
}

/// The welcome window. A folder named on the command line opens at once.
private struct Welcome: View {
    let recent: RecentFolders
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WelcomeView(recent: recent.urls) { openWindow(value: $0) }
            .task {
                guard CommandLine.arguments.count > 1 else { return }
                openWindow(value: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
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
                if let url = FolderChooser.choose() { openWindow(value: url) }
            }
            .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(recent.urls, id: \.self) { url in
                    Button(url.lastPathComponent) { openWindow(value: url) }
                }
            }
            .disabled(recent.urls.isEmpty)
        }
    }
}
