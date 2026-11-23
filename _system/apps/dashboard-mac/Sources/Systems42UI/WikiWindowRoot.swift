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
                if let missing = session.missingParts {
                    // The folder was moved or removed while the window was open.
                    chooseAgain(PreflightFailure(folder: folder, missing: missing), heading: "The folder is gone or incomplete")
                } else {
                    WikiWindow(session: session)
                }
            case .failed(let failure)?:
                chooseAgain(failure, heading: "This folder is not a Systems42 wiki")
            }
        }
        .opensDroppedFolders()
        .onAppear {
            if case .session(let session)? = result {
                OpenSessions.shared.register(session)
                session.startWatching()
            }
        }
        .onDisappear {
            if case .session(let session)? = result {
                OpenSessions.shared.unregister(session)
                session.stopWatching()
            }
        }
        .task {
            let loaded = await OpenedWiki.open(folder)
            if case .session(let session) = loaded {
                OpenSessions.shared.register(session)
                session.startWatching()
                opened(folder)
                DeepLinkRouter.shared.sessionOpened(session)
            }
            if case .failed = loaded { DeepLinkRouter.shared.openFailed(folder) }
            result = loaded
        }
    }

    private func chooseAgain(_ failure: PreflightFailure, heading: String) -> some View {
        PreflightFailureView(failure: failure, chooseAnother: {
            guard let other = FolderChooser.choose() else { return }
            openWindow.openWiki(other)
            dismiss()
        }, heading: heading)
    }
}
