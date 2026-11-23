import SwiftUI
import Systems42Kit

/// Help > Systems42 Dashboard Help: the dashboard's help text.
public struct HelpWindow: View {
    public static let windowID = "help"
    private let page = renderPage(HelpText.markdown, resolve: { _ in .missing }, title: { _ in nil })

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
