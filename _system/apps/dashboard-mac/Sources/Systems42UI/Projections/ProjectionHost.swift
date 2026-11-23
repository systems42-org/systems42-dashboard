import SwiftUI
import Systems42Kit

/// Draws the projection a section is shown in, and decides which projections a section offers.
/// A mode is the name of a projection page of the metamodel. The graph diagrams (context, building blocks,
/// deployment, data model, term network) are drawn in a web view by a later issue: they join this host
/// by adding their projection name to `nativeProjections` and a case to `ProjectionView`.
struct ProjectionHost: View {
    /// The projections the app draws natively, by the name of their projection page. Open debt (CON-006):
    /// the metamodel does not say how a projection is drawn, so this list is code. The hierarchy has no
    /// page of its own: `story-map` reads it, and the story map view switches between map and outline.
    static let nativeProjections = [storyMapMode, matrixMode, backlogMode]
    static let storyMapMode = "story-map", matrixMode = "goal-coverage", backlogMode = "backlog-ranking"

    /// `list`, then the projections the section's types declare, the wiki's metamodel has a page for
    /// (`Projections.available`) and the app draws. In the order the types declare them.
    static func modes(for section: WikiSection, metamodel: Metamodel) -> [String] {
        let available = Set(metamodel.projections.map(\.name))
        var modes = [ListModel.listMode]
        for type in section.types.compactMap({ metamodel.type(named: $0) }) {
            for name in type.projections where nativeProjections.contains(name) && available.contains(name) && !modes.contains(name) {
                modes.append(name)
            }
        }
        return modes
    }

    /// The label of a mode in the switch.
    static func label(ofMode mode: String, metamodel: Metamodel) -> String {
        if mode == ListModel.listMode { return FieldLabel.text(mode) }
        let label = metamodel.label(ofProjection: mode)
        return label.isEmpty ? FieldLabel.text(mode) : label
    }

    let session: WikiSession
    let mode: String
    @State private var outline = false

    var body: some View {
        ProjectionView(session: session, model: session.projections, mode: mode, outline: $outline)
            .task(id: ProjectionsModel.Key(revision: session.revision, agreedOnly: session.agreedOnly)) {
                await session.projections.load()
            }
    }
}

/// The view of one projection. The one place that maps a mode to a drawing.
private struct ProjectionView: View {
    let session: WikiSession
    let model: ProjectionsModel
    let mode: String
    @Binding var outline: Bool

    var body: some View {
        content
            .opacity(model.isCurrent ? 1 : 0.45)
            .overlay(alignment: .top) {
                if !model.isCurrent && model.data != nil {
                    ProgressView("Updating").controlSize(.small).padding(6).background(.regularMaterial, in: Capsule()).padding(.top, 8)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let data = model.data {
            let selected = session.selectedPage
            let onSelect: (PageRef) -> Void = { model.select($0) }
            switch mode {
            case ProjectionHost.matrixMode:
                if data.matrix.isEmpty { Hint(mode: mode) } else { GoalMatrixView(model: data.matrix, selected: selected, onSelect: onSelect) }
            case ProjectionHost.backlogMode:
                if data.backlog.isEmpty { Hint(mode: mode) } else { BacklogView(rows: data.backlog, selected: selected, onSelect: onSelect) }
            case ProjectionHost.storyMapMode:
                if data.storyMap.isEmpty && data.outline.isEmpty {
                    Hint(mode: mode)
                } else {
                    VStack(spacing: 0) {
                        Picker("Show", selection: $outline) {
                            Text("Story map").tag(false)
                            Text("Outline").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        .padding(8)
                        .accessibilityLabel("Show the requirements as a story map or as an outline")
                        if outline {
                            HierarchyView(model: model, roots: data.outline, revision: data.revision, selected: selected, onSelect: onSelect)
                        } else {
                            StoryMapView(model: data.storyMap, selected: selected, onSelect: onSelect)
                        }
                    }
                }
            default:
                // A mode the app does not draw. `WikiSession.showsProjection` keeps the host away from it.
                Text("This view is not available.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Hint: View {
    let mode: String

    var body: some View {
        Text(ProjectionHint.text(for: mode))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

/// The mode switch of the toolbar. A segmented control for two modes, a menu for more.
struct ModePicker: View {
    let modes: [String]
    let current: String
    let label: (String) -> String
    let choose: (String) -> Void

    private var options: some View {
        ForEach(modes, id: \.self) { Text(label($0)).tag($0) }
    }

    var body: some View {
        // The switch shows once a section offers a second mode.
        if modes.count > 1 {
            let binding = Binding(get: { current }, set: { choose($0) })
            if modes.count > 2 {
                Picker("Mode", selection: binding) { options }
                    .pickerStyle(.menu)
                    .help("Show this section as a list or as a projection")
            } else {
                Picker("Mode", selection: binding) { options }
                    .pickerStyle(.segmented)
                    .help("Show this section as a list or as a projection")
            }
        }
    }
}

/// "Agreed only" (FR-022): every list and projection shows only the agreed pages.
struct AgreedOnlyToggle: View {
    @Bindable var session: WikiSession

    var body: some View {
        Toggle("Agreed only", systemImage: "checkmark.seal", isOn: $session.agreedOnly)
            .help("Show only agreed pages, in lists, counts and projections")
    }
}
