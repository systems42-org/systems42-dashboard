import SwiftUI

/// What the app shows before a wiki is open.
public struct WelcomeView: View {
    let recent: [URL]
    let open: (URL) -> Void

    public init(recent: [URL], open: @escaping (URL) -> Void) {
        self.recent = recent
        self.open = open
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(AppInfo.windowTitle).font(.largeTitle)
            Text("Open the folder of a Systems42 wiki, or drop it here.").foregroundStyle(.secondary)
            Button("Open Folder…") {
                if let url = FolderChooser.choose() { open(url) }
            }
            .keyboardShortcut("o")
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent").font(.headline)
                    ForEach(recent, id: \.self) { url in
                        Button(url.lastPathComponent) { open(url) }.buttonStyle(.link).help(url.path)
                    }
                }
            }
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 320)
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: \.hasDirectoryPath) else { return false }
            open(folder)
            return true
        }
    }
}
