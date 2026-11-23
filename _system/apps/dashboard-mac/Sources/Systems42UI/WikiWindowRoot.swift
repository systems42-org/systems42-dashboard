import SwiftUI

/// The content of a wiki window: loads the folder, then shows the wiki or why it failed.
public struct WikiWindowRoot: View {
    let folder: URL
    let opened: (URL) -> Void
    @State private var result: OpenedWiki?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    public init(folder: URL, opened: @escaping (URL) -> Void) {
        self.folder = folder
        self.opened = opened
    }

    public var body: some View {
        Group {
            switch result {
            case nil:
                ProgressView().frame(minWidth: 400, minHeight: 300)
            case .session(let session)?:
                WikiWindow(session: session)
            case .failed(let failure)?:
                PreflightFailureView(failure: failure) {
                    guard let other = FolderChooser.choose() else { return }
                    openWindow.openWiki(other)
                    dismiss()
                }
            }
        }
        .opensDroppedFolders()
        .onDisappear {
            if case .session(let session)? = result { OpenSessions.shared.unregister(session) }
        }
        .task {
            let loaded = await OpenedWiki.open(folder)
            if case .session(let session) = loaded {
                OpenSessions.shared.register(session)
                opened(folder)
            }
            result = loaded
        }
    }
}
