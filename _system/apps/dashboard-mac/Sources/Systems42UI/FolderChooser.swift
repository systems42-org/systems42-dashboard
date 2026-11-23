import AppKit

/// The system panel that asks for a wiki folder.
public enum FolderChooser {
    @MainActor public static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url.map(WikiFolders.standardized) : nil
    }
}
