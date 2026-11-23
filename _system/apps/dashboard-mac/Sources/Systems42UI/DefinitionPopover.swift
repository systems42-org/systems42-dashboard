import SwiftUI
import Systems42Kit

/// A short explanation shown beside a link or a label.
struct Definition: Identifiable, Equatable {
    let title: String
    let text: String
    var id: String { title }
}

struct DefinitionPopover: View {
    let definition: Definition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: definition.title).font(.headline)
            Text(verbatim: definition.text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 320, alignment: .leading)
        .padding(12)
    }
}

/// What a link in the page can do. The page view fills it in. Outside a page the links do nothing.
struct PageLinks {
    var open: @MainActor (LinkAction) -> Void = { _ in }
    /// The popover for a click. `optionHeld` asks for the definition of a page instead of opening it.
    var definition: @MainActor (LinkAction, _ optionHeld: Bool) -> Definition? = { _, _ in nil }
}

private struct PageLinksKey: EnvironmentKey {
    static let defaultValue = PageLinks()
}

extension EnvironmentValues {
    var pageLinks: PageLinks {
        get { self[PageLinksKey.self] }
        set { self[PageLinksKey.self] = newValue }
    }
}

/// Styled text whose links work: a click opens, and an anchor or an Option-click shows its definition.
struct InlineTextView: View {
    let content: InlineContent
    var font: Font?
    @Environment(\.pageLinks) private var links
    @Environment(\.pageMarks) private var marks
    @State private var shown: Definition?

    init(_ inlines: [Inline], font: Font? = nil) {
        content = InlineContent(inlines)
        self.font = font
    }

    var body: some View {
        Text(marks.apply(to: content.text))
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard let action = LinkAction(url: url) else { return .discarded }
                let optionHeld = NSEvent.modifierFlags.contains(.option)
                if let definition = links.definition(action, optionHeld) {
                    shown = definition
                } else {
                    links.open(action)
                }
                return .handled
            })
            .popover(item: $shown) { DefinitionPopover(definition: $0) }
    }
}
