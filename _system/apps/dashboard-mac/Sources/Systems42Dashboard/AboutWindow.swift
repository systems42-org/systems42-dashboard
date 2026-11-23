import SwiftUI
import Systems42UI

/// The About window: the app, and the wiki of the window that was focused when the reader chose About.
struct AboutScene: Scene {
    var body: some Scene {
        Window("About \(AppInfo.windowTitle)", id: AboutWindowRoot.windowID) {
            AboutWindowRoot()
        }
        .windowResizability(.contentSize)
    }
}
