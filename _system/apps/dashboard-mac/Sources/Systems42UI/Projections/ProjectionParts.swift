import SwiftUI
import Systems42Kit

/// A short value as a small text chip. The text carries the meaning, the shape only sets it apart.
struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .background(.quaternary, in: Capsule())
    }
}

/// A button that Tab reaches and Return and Space press, with the page it opens as its action.
struct OpenButton<Content: View>: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action, label: content)
            .buttonStyle(.plain)
            .focusable()
            .onKeyPress(.return) { action(); return .handled }
            .onKeyPress(.space) { action(); return .handled }
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Colours of the projections. They come from the area of requirements, and from system colours, so they follow light and dark.
enum ProjectionStyle {
    static let accent = Area.requirements.color
    static let warning = Color.orange
    static let border = Color.secondary.opacity(0.35)
}
