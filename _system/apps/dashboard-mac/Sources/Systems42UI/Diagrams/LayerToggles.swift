import SwiftUI

/// The frame colour of a page type in the term network, as the dashboard's style sheet has it (light, dark).
/// A type the sheet has no colour for takes the colour of the rest.
enum LayerColour {
    static func color(prefix: String, dark: Bool) -> Color {
        let pair: (light: UInt32, dark: UInt32)
        switch prefix.lowercased() {
        case "dt": pair = (0x2F6FB3, 0x5FA3E8)
        case "stk": pair = (0x8A5C10, 0xE6B667)
        case "eif": pair = (0x59418C, 0xB39AD6)
        case "goal": pair = (0x7A6014, 0xE0C068)
        case "bb": pair = (0x1F5FA8, 0x7FB8FF)
        default: pair = (0x4D5A72, 0xAAB4C9)
        }
        let value = dark ? pair.dark : pair.light
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// One toggle per page type that terms link to. Each shows the type's colour and the links it adds.
struct LayerToggles: View {
    let model: TermNetworkModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !model.layers.isEmpty {
            HStack(spacing: 8) {
                Text("Add:").foregroundStyle(.secondary)
                ForEach(model.layers) { layer in
                    let on = Binding(get: { model.isOn(layer.id) }, set: { _ in model.toggle(layer.id) })
                    Toggle(isOn: on) {
                        HStack(spacing: 5) {
                            Circle().fill(LayerColour.color(prefix: layer.prefix, dark: scheme == .dark)).frame(width: 9, height: 9)
                            Text(verbatim: layer.label)
                            Text("\(layer.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel("\(layer.label), adds \(layer.count) links")
                    .help("Show the \(layer.label) pages that terms link to")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
    }
}
