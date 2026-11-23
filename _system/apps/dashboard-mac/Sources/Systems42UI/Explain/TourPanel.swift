import SwiftUI
import Systems42Kit

/// The bar at the bottom of the wiki window while the tour runs: position, step text, Back, Next, Stop.
struct TourPanel: View {
    @Bindable var tour: TourModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if tour.isActive, let stop = tour.currentStop {
            let position = "Step \(tour.current + 1) of \(tour.steps.count)"
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(position): \(stop.title)").font(.headline)
                    Text(stop.step.text)
                    if let projection = stop.projection {
                        Text("Projection offered here: \(projection)").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                HStack {
                    Button("Back") { tour.previous() }
                        .shortcut(Shortcuts.previousTourStep)
                        .disabled(tour.current == 0)
                        .accessibilityLabel("Previous step")
                    Button(tour.current + 1 >= tour.steps.count ? "Finish" : "Next") { tour.next() }
                        .shortcut(Shortcuts.nextTourStep)
                        .accessibilityLabel(tour.current + 1 >= tour.steps.count ? "Finish the tour" : "Next step")
                    if stop.step.showsType == nil {
                        Button("Open The Method") { openWindow(id: MethodWindow.windowID) }
                            .accessibilityLabel("Open The Method window")
                    }
                    if !tour.isOnStep {
                        Button("Back to this step") { tour.returnToStep() }
                            .accessibilityLabel("Return to the current step")
                    }
                    Spacer()
                    Button("Stop") { tour.stop() }
                        .shortcut(Shortcuts.stopTour)
                        .accessibilityLabel("Stop the tour")
                }
            }
            .padding(12)
            .background(.bar)
            .onChange(of: tour.revision) { _, _ in tour.followWiki() }
        }
    }
}
