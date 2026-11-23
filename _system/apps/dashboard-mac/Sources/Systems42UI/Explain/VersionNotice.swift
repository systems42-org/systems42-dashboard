import SwiftUI
import Systems42Kit

/// What a reader can ask the Metamodel window to explain.
enum ExplainTarget {
    case link(LinkTarget)
    case section(WikiSection.ID)
    case versionNotice
}

/// Opens the Metamodel window on an entry. The default does nothing, so views outside a wiki window stay quiet.
struct ExplainAction {
    var run: @MainActor (ExplainTarget) -> Void = { _ in }

    @MainActor func callAsFunction(_ target: ExplainTarget) { run(target) }

    /// Shows the target in the model. A target with no entry shows a line that says so.
    @MainActor
    static func apply(_ target: ExplainTarget, to model: MetamodelModel) {
        switch target {
        case .link(let link): if !model.show(link) { model.showNoEntry(for: link) }
        case .section(let id): if !model.show(section: id) { model.showNoEntry(forSection: id) }
        case .versionNotice: model.showVersionNotice()
        }
    }
}

private struct ExplainKey: EnvironmentKey {
    static let defaultValue = ExplainAction()
}

extension EnvironmentValues {
    var explain: ExplainAction {
        get { self[ExplainKey.self] }
        set { self[ExplainKey.self] = newValue }
    }
}

/// One line under the toolbar when the wiki's metamodel is not a supported version (FR-043).
struct VersionNoticeLine: View {
    let session: WikiSession
    @Environment(\.explain) private var explain

    var body: some View {
        if let notice = session.explainer.versionNotice {
            Button { explain(.versionNotice) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(verbatim: notice.line).lineLimit(2)
                    Spacer(minLength: 8)
                    Text("Explain").foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the metamodel explanation")
        }
    }
}

/// The text the notice opens in the Metamodel window.
struct VersionExplanationView: View {
    let notice: (line: String, explanation: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: notice.line).font(.title3.bold())
            Text(verbatim: notice.explanation)
        }
        .padding(20)
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
    }
}
