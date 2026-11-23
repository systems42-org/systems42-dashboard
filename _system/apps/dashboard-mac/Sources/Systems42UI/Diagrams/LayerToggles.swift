import AppKit
import SwiftUI
import Systems42Kit

/// The colour of a page type's layer: swatch of the toggle and frame of its nodes in the term network.
enum LayerColour {
    /// Open debt (CON-006): the colours the dashboard's style sheet gives some types (light, dark), by id prefix
    /// in lower case. The area colour (`Area.color`) cannot tell types of one area apart, and the dashboard does.
    /// A type not in this table takes the colour of its area. The metamodel holds no colour.
    static let dashboardFrames: [String: (light: UInt32, dark: UInt32)] = [
        "stk": (0x8A5C10, 0xE6B667), "eif": (0x59418C, 0xB39AD6), "goal": (0x7A6014, 0xE0C068), "bb": (0x1F5FA8, 0x7FB8FF),
    ]

    private static func hex(_ value: UInt32) -> String { String(format: "#%06x", value) }

    /// The area of the section a type belongs to.
    static func area(ofType name: String, in metamodel: Metamodel) -> Area? {
        metamodel.sections.first { $0.types.contains(name) }?.area
    }

    /// `#rrggbb` of an area colour as it looks in the light or the dark appearance.
    static func hex(of area: Area?, dark: Bool) -> String {
        guard let area, let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return hex(dark ? 0xAAB4C9 : 0x4D5A72) }
        var result = hex(dark ? 0xAAB4C9 : 0x4D5A72)
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = NSColor(area.color).usingColorSpace(.sRGB) {
                let value = (UInt32(rgb.redComponent * 255) << 16) | (UInt32(rgb.greenComponent * 255) << 8) | UInt32(rgb.blueComponent * 255)
                result = hex(value)
            }
        }
        return result
    }

    /// Light and dark `#rrggbb` of a layer.
    static func pair(of layer: TermNetworkModel.Layer, in metamodel: Metamodel) -> [String] {
        if let known = dashboardFrames[layer.prefix.lowercased()] { return [hex(known.light), hex(known.dark)] }
        let area = area(ofType: layer.id, in: metamodel)
        return [hex(of: area, dark: false), hex(of: area, dark: true)]
    }

    /// The frame colours the page draws the nodes of these layers with, by id prefix.
    static func frames(of layers: [TermNetworkModel.Layer], in metamodel: Metamodel) -> [String: [String]] {
        var frames: [String: [String]] = [:]
        for layer in layers where frames[layer.prefix] == nil { frames[layer.prefix] = pair(of: layer, in: metamodel) }
        return frames
    }

    static func color(of layer: TermNetworkModel.Layer, in metamodel: Metamodel, dark: Bool) -> Color {
        let pair = pair(of: layer, in: metamodel)
        let text = dark ? pair[1] : pair[0]
        let value = UInt32(text.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Puts its children in rows and starts a new row when one is full.
struct WrappingRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(width: bounds.width, subviews: subviews)
        for (subview, point) in zip(subviews, laid.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}

/// One toggle per page type that terms link to. Each shows the type's colour and the links it adds.
/// The row wraps when there are many types.
struct LayerToggles: View {
    let layers: [TermNetworkModel.Layer]
    let metamodel: Metamodel
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !layers.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Add:").foregroundStyle(.secondary)
                WrappingRow {
                    ForEach(layers) { layer in
                        let on = Binding(get: { isOn(layer.id) }, set: { _ in toggle(layer.id) })
                        Toggle(isOn: on) {
                            HStack(spacing: 5) {
                                Circle().fill(LayerColour.color(of: layer, in: metamodel, dark: scheme == .dark)).frame(width: 9, height: 9)
                                Text(verbatim: layer.label)
                                Text("\(layer.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .toggleStyle(.button)
                        .accessibilityLabel("\(layer.label), adds \(layer.count) links")
                        .help("Show the \(layer.label) pages that terms link to")
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }
}
