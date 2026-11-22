import SwiftUI

/// A thin bar that fills with the share of agreed pages.
struct MaturityBar: View {
    let share: Double

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.secondary).frame(width: box.size.width * share)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Agreed")
        .accessibilityValue("\(Int((share * 100).rounded())) percent")
    }
}
