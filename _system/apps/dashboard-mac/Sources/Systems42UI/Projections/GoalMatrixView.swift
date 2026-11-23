import SwiftUI
import Systems42Kit

/// The goal coverage matrix (FR-036): goals as rows, epics and use cases as columns, enablers set apart.
/// The goal column stays put while the columns scroll. Every mark is also text: under the matrix each
/// goal lists the requirements that serve it.
struct GoalMatrixView: View {
    let model: MatrixModel
    let selected: PageRef?
    let onSelect: (PageRef) -> Void
    @State private var hovered: String?
    @FocusState private var focused: String?

    private static let goalWidth: CGFloat = 230, cellWidth: CGFloat = 64, rowHeight: CGFloat = 48, headerHeight: CGFloat = 62
    private static let gapWidth: CGFloat = 16

    var body: some View {
        ScrollView(.vertical) { content(scrolls: true) }
    }

    /// The matrix and the text under it. `scrolls: false` leaves out the scroll view, which an offscreen render does not draw.
    func content(scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
                Text(caption).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .frame(height: 20, alignment: .leading)
                HStack(alignment: .top, spacing: 0) {
                    goalColumn
                    if scrolls { ScrollView(.horizontal) { columnGrid } } else { columnGrid }
                }
                Text("A mark means the column's requirement names the goal. A goal with no mark may be served by features or stories: the lists below name them.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                served
        }
        .padding(12)
    }

    /// The title of the column that is hovered or has the focus.
    private var caption: String {
        let key = focused ?? hovered
        if let key, let column = model.columns.first(where: { $0.item.key == key }) { return column.item.text }
        return "Hover over or focus a column to see its title."
    }

    // MARK: Goal column

    private var goalColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Goal / requirement").font(.caption).foregroundStyle(.secondary)
                .frame(width: Self.goalWidth, height: Self.headerHeight, alignment: .bottomLeading)
            ForEach(model.rows, id: \.item.key) { row in
                OpenButton(label: row.accessibilityLabel, selected: selected == row.item.ref, action: { if let ref = row.item.ref { onSelect(ref) } }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.item.text).font(.callout).lineLimit(2).truncationMode(.tail)
                        if row.gap {
                            Text("Gap: no requirement serves it").font(.caption2.bold()).foregroundStyle(ProjectionStyle.warning)
                        } else if row.acceptedGap {
                            Text("No agreed requirement serves it").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: Self.goalWidth, height: Self.rowHeight, alignment: .leading)
                    .background(selected == row.item.ref ? Color.accentColor.opacity(0.15) : .clear)
                }
                .help(row.item.title)
                Divider()
            }
        }
    }

    // MARK: Columns

    private var columnGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(model.columns.enumerated()), id: \.element.item.key) { index, column in
                    separator(before: index)
                    header(column)
                }
            }
            .frame(height: Self.headerHeight)
            ForEach(model.rows, id: \.item.key) { row in
                HStack(spacing: 0) {
                    ForEach(Array(model.columns.enumerated()), id: \.element.item.key) { index, column in
                        separator(before: index)
                        cell(row: row, index: index)
                    }
                }
                .frame(height: Self.rowHeight)
                Divider()
            }
        }
    }

    /// A gap before the first enabler column, so the enablers form their own group.
    @ViewBuilder private func separator(before index: Int) -> some View {
        if index == model.enablerStart {
            Rectangle().fill(ProjectionStyle.border).frame(width: 1).padding(.horizontal, Self.gapWidth / 2 - 0.5)
        }
    }

    private func header(_ column: MatrixModel.Column) -> some View {
        let key = column.item.key
        return OpenButton(label: column.accessibilityLabel, selected: selected == column.item.ref, action: { if let ref = column.item.ref { onSelect(ref) } }) {
            VStack(spacing: 1) {
                Text(column.item.id).font(.system(.caption, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                if column.untraced {
                    Text("no goal").font(.caption2.bold()).foregroundStyle(ProjectionStyle.warning)
                } else if column.enabler {
                    Text("enabler").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.cellWidth, height: Self.headerHeight - 6)
            .background(column.untraced ? ProjectionStyle.warning.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .focused($focused, equals: key)
        .onHover { inside in hovered = inside ? key : (hovered == key ? nil : hovered) }
        .help(column.item.text)
    }

    private func cell(row: MatrixModel.Row, index: Int) -> some View {
        ZStack {
            if row.marks[index] {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ProjectionStyle.accent)
            }
        }
        .frame(width: Self.cellWidth, height: Self.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.cellLabel(row: row, column: index))
    }

    // MARK: Text under the matrix

    private var served: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.rows, id: \.item.key) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.item.text).font(.callout.bold()).lineLimit(2).truncationMode(.tail)
                    if row.serving.isEmpty {
                        Text("No requirement serves this goal.").foregroundStyle(ProjectionStyle.warning)
                    } else {
                        ForEach(row.serving, id: \.key) { item in
                            Button { if let ref = item.ref { onSelect(ref) } } label: {
                                Text("\(item.text) (\(item.status))").lineLimit(1).truncationMode(.tail)
                            }
                            .buttonStyle(.link)
                            .accessibilityLabel("\(row.item.id) is served by \(item.text), \(item.status)")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}
