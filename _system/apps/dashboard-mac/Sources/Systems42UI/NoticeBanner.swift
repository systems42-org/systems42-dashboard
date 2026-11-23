import SwiftUI

/// The notice of a link, at the top of the frontmost wiki window (or of the Welcome window while no wiki
/// window is open). A notice without a button goes away by itself, one with a button stays until dismissed.
struct NoticeBanner: View {
    let board: NoticeBoard
    let window: NoticeBoard.Window
    @Environment(\.controlActiveState) private var active
    private let sessions = OpenSessions.shared

    var body: some View {
        if let notice = board.current,
           NoticeBoard.isVisible(in: window, isKey: active == .key, wikiWindowsOpen: !sessions.all().isEmpty) {
            HStack(spacing: 10) {
                Text(verbatim: notice.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let button = notice.button {
                    Button(button.title) {
                        board.dismiss()
                        button.run()
                    }
                }
                Button("Dismiss", systemImage: "xmark") { board.dismiss() }.labelStyle(.iconOnly)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .padding(10)
            .frame(maxWidth: 640)
            .accessibilityElement(children: .combine)
            .task(id: notice.id) {
                guard notice.button == nil else { return }
                try? await Task.sleep(for: .seconds(NoticeBoard.lifetime))
                board.expireIfDue(at: Date())
            }
        }
    }
}
