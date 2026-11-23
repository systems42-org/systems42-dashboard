import SwiftUI

/// The text a field's help popover shows: what the metamodel says about the field and the values it allows.
enum FieldHelp {
    static func text(doc: String?, values: [String]) -> String? {
        var lines: [String] = []
        if let doc, !doc.isEmpty { lines.append(doc) }
        if !values.isEmpty { lines.append("Values: " + values.joined(separator: ", ")) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private struct FieldHelpModifier: ViewModifier {
    let title: String
    let text: String?
    @State private var shown = false

    func body(content: Content) -> some View {
        if let text {
            // A plain button: it takes focus like any control, opens the popover on a click or the space bar
            // (not on focus alone), and carries the help text for VoiceOver and the tooltip.
            Button { shown.toggle() } label: { content }
                .buttonStyle(.plain)
                .help(text)
                .accessibilityHint(text)
                .popover(isPresented: $shown, arrowEdge: .bottom) {
                    DefinitionPopover(definition: Definition(title: title, text: text))
                }
        } else {
            content
        }
    }
}

extension View {
    /// Shows the help text in a popover on a click or the space bar. Without text the view stays as it is.
    func fieldHelp(title: String, _ text: String?) -> some View {
        modifier(FieldHelpModifier(title: title, text: text))
    }
}
