import AppKit
import SwiftUI
import Systems42UI

@main
struct DashboardApp: App {
    @State private var recent = RecentFolders.shared
    /// The folder named on the command line, read once at launch and opened once.
    @State private var launch = LaunchFolder(
        WikiFolders.fromArguments(Array(CommandLine.arguments.dropFirst()), currentDirectory: FileManager.default.currentDirectoryPath))

    init() {
        // A check for the build script and CI: no window, no menu.
        if let status = DiagramAssetCheck.handle(Array(CommandLine.arguments.dropFirst())) { exit(status) }
        // `swift run` starts a bare executable. Make it a normal app with a window and a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        // A link from outside may name a wiki that is only recent.
        DeepLinkRouter.shared.configure(recent: { RecentFolders.shared.urls })
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
            HelpCommands()
            AboutCommands()
            OpenCommands(recent: recent)
            ViewCommands()
            GoCommands()
            PageCommands()
            SearchCommands()
            MetamodelCommands()
            MethodCommands()
        }
        Window("The Method", id: MethodWindow.windowID) {
            MethodWindow()
        }
        Window("Systems42 Dashboard Help", id: HelpWindow.windowID) {
            HelpWindow()
        }
        AboutScene()
        WindowGroup("Metamodel", id: MetamodelWindowRoot.windowID, for: URL.self) { $folder in
            if let folder { MetamodelWindowRoot(folder: folder) }
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
