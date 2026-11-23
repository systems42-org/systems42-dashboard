import SwiftUI
import Systems42Kit

/// The id with its badges, the title, and the formats the page follows.
struct PageHead: View {
    let model: PageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: model.page.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                ForEach(Array(model.head.enumerated()), id: \.offset) { index, badge in
                    Text(verbatim: badge.value)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .fieldHelp(title: badge.label, model.headHelp[index])
                        .accessibilityLabel("\(badge.label): \(badge.value)")
                }
            }
            Text(verbatim: model.page.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
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
    @Environment(\.explain) private var explain

    var body: some View {
        if let anchor = item.anchor {
            Button(item.label) { explain(.link(.anchor(anchor.name))) }
                .buttonStyle(.link)
                .font(.caption)
                .help("Open the entry for \(anchor.title)")
        } else {
            Text(verbatim: item.label).font(.caption)
        }
    }
}
