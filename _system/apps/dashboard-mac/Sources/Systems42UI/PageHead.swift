import SwiftUI
import Systems42Kit

/// The id with its badges, the title, and the formats the page follows.
struct PageHead: View {
    let model: PageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: model.page.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                ForEach(Array(model.head.enumerated()), id: \.offset) { _, badge in
                    Text(verbatim: badge.value)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .help(badge.doc.map { "\(badge.label): \($0)" } ?? badge.label)
                        .accessibilityLabel("\(badge.label): \(badge.value)")
                }
            }
            Text(verbatim: model.page.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            if !model.followItems.isEmpty {
                HStack(spacing: 6) {
                    Text("Follows").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(model.followItems.enumerated()), id: \.offset) { _, item in FollowLabel(item: item) }
                }
            }
        }
    }
}

/// A "follows" label. One that names an anchor shows its definition on a click.
private struct FollowLabel: View {
    let item: FollowItem
    @State private var shown = false

    var body: some View {
        if let anchor = item.anchor {
            Button(item.label) { shown = true }
                .buttonStyle(.link)
                .font(.caption)
                .popover(isPresented: $shown) {
                    DefinitionPopover(definition: Definition(title: anchor.title, text: anchor.definition))
                }
        } else {
            Text(verbatim: item.label).font(.caption)
        }
    }
}
