import SwiftUI

/// The notice of a link, at the top of a window. It stays until the reader dismisses it.
struct NoticeBanner: View {
    let board: NoticeBoard

    var body: some View {
        if let notice = board.current {
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
        }
    }
}
