import SwiftUI
import Systems42Kit

/// The Method window: the three loops and how they feed each other (FR-010, FR-011).
public struct MethodWindow: View {
    public static let windowID = "method"
    private let page = renderPage(MethodText.markdown, resolve: { _ in .missing }, title: { _ in nil })

    public init() {}

    public var body: some View {
        ScrollView {
            BlockList(blocks: page.blocks)
                .textSelection(.enabled)
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

/// Help > The Method.
public struct MethodCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .help) {
            Button("The Method") { openWindow(id: MethodWindow.windowID) }
        }
    }
}
