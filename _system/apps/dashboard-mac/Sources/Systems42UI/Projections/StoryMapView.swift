import SwiftUI
import Systems42Kit

/// The story map (FR-047): the backbone across the top, one row per release, a card per feature or story.
struct StoryMapView: View {
    let model: StoryMapModel
    let selected: PageRef?
    let onSelect: (PageRef) -> Void

    private static let columnWidth: CGFloat = 200, labelWidth: CGFloat = 84

    var body: some View {
        ScrollView([.horizontal, .vertical]) { content(lazy: true) }
    }

    /// The map. `lazy: false` makes plain stacks, which an offscreen render draws.
    @ViewBuilder func content(lazy: Bool) -> some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) { sections }.padding(12)
        } else {
            VStack(alignment: .leading, spacing: 12) { sections }.padding(12)
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            if model.releases.isEmpty {
                Text("No feature or story yet.").foregroundStyle(.secondary).padding(.leading, Self.labelWidth + 8)
            }
            ForEach(model.releases, id: \.self) { release in
                HStack(alignment: .top, spacing: 8) {
                    Text(release).font(.callout.bold()).frame(width: Self.labelWidth, alignment: .leading)
                        .accessibilityLabel("Release \(release)")
                    ForEach(Array(model.columns.enumerated()), id: \.element.item.key) { index, column in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.cards(column: index, release: release), id: \.item.key) { card in
                                CardView(card: card, selected: selected == card.item.ref, onSelect: onSelect)
                            }
                        }
                        .frame(width: Self.columnWidth, alignment: .topLeading)
                    }
                }
            }
        } header: {
            HStack(alignment: .top, spacing: 8) {
                Text("Release").font(.caption).foregroundStyle(.secondary).frame(width: Self.labelWidth, alignment: .leading)
                ForEach(model.columns, id: \.item.key) { column in
                    BackboneHeader(column: column, selected: selected == column.item.ref, onSelect: onSelect)
                        .frame(width: Self.columnWidth, alignment: .topLeading)
                }
            }
            .padding(.vertical, 6)
            .background(.background)
        }
    }
}

private struct BackboneHeader: View {
    let column: StoryMapModel.Column
    let selected: Bool
    let onSelect: (PageRef) -> Void

    var body: some View {
        OpenButton(label: column.accessibilityLabel, selected: selected, action: { if let ref = column.item.ref { onSelect(ref) } }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(column.item.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Chip(text: column.level)
                }
                Text(column.item.title).font(.callout.bold()).lineLimit(2).truncationMode(.tail)
                Text(column.item.status).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProjectionStyle.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : ProjectionStyle.accent.opacity(0.5), lineWidth: selected ? 2 : 1))
        }
    }
}

private struct CardView: View {
    let card: StoryMapModel.Card
    let selected: Bool
    let onSelect: (PageRef) -> Void

    var body: some View {
        OpenButton(label: card.accessibilityLabel, selected: selected, action: { if let ref = card.item.ref { onSelect(ref) } }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(card.item.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(card.item.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(card.item.title).font(.callout).lineLimit(3).truncationMode(.tail)
                HStack(spacing: 4) {
                    Chip(text: card.level)
                    if !card.priority.isEmpty { Chip(text: card.priority) }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.accentColor : ProjectionStyle.border, lineWidth: selected ? 2 : 1))
        }
    }
}
