import SwiftUI
import Systems42UI

@main
struct DashboardApp: App {
    var body: some Scene {
        Window(AppInfo.windowTitle, id: "main") {
            Color.clear.frame(minWidth: 800, minHeight: 600)
        }
    }
}
