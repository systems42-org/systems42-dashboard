import SwiftUI
import Systems42Kit

/// How a callout looks. The kind is the word after `[!` in the page. An unknown kind gets the plain look.
struct CalloutStyle {
    let symbol: String
    let color: Color

    init(kind: String) {
        switch kind {
        case "warning", "caution", "danger", "error", "bug": (symbol, color) = ("exclamationmark.triangle", .orange)
        case "tip", "success", "check", "done": (symbol, color) = ("lightbulb", .green)
        case "assumption", "question", "help", "faq": (symbol, color) = ("questionmark.circle", .purple)
        case "note", "info", "abstract", "summary", "todo": (symbol, color) = ("info.circle", .blue)
        default: (symbol, color) = ("text.bubble", .gray)
        }
    }
}

/// One view per `Block` case.
struct BlockView: View {
    let block: Block

    /// What a block is drawn as. One name per case, so a test can check that none is missing.
    enum Kind: Hashable {
        case heading, paragraph, orderedList, bulletList, table, codeListing, callout, quote, rule, sourceListing
    }

    static func kind(of block: Block) -> Kind {
        switch block {
        case .heading: .heading
        case .paragraph: .paragraph
        case .list(let ordered, _): ordered ? .orderedList : .bulletList
        case .table: .table
        case .code: .codeListing
        case .callout: .callout
        case .quote: .quote
        case .rule: .rule
        // Diagrams are drawn by a later issue. Until then the reader sees the source.
        case .diagram: .sourceListing
        }
    }

    var body: some View {
        switch block {
        case .heading(let level, let inlines):
            InlineTextView(inlines, font: Self.font(forHeading: level)).fontWeight(.semibold).padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let inlines):
            InlineTextView(inlines)
        case .list(let ordered, let items):
            ListBlock(ordered: ordered, items: items)
        case .table(let header, let rows):
            TableBlock(header: header, rows: rows)
        case .code(_, let text):
            CodeBlock(text: text)
        case .callout(let kind, let title, let inner):
            CalloutBlock(kind: kind, title: title, inner: inner)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(.quaternary).frame(width: 3)
                BlockList(blocks: inner).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider().padding(.vertical, 4)
        case .diagram(let language, let text):
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(language) source").font(.caption).foregroundStyle(.secondary)
                CodeBlock(text: text)
            }
        }
    }

    private static func font(forHeading level: Int) -> Font {
        switch level {
        case ...1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }
}

/// Blocks one below the other.
struct BlockList: View {
    let blocks: [Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }
}

private struct ListBlock: View {
    let ordered: Bool
    let items: [[Block]]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: ordered ? "\(index + 1)." : "•")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    BlockList(blocks: item)
                }
            }
        }
    }
}

/// A table scrolls sideways inside its own box.
private struct TableBlock: View {
    let header: [[Inline]]
    let rows: [[[Inline]]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        InlineTextView(cell).fontWeight(.semibold)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in InlineTextView(cell) }
                    }
                }
            }
            .padding(10)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}

/// A listing. A long line scrolls inside the box instead of wrapping.
private struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: text)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: true, vertical: true)
                .padding(10)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CalloutBlock: View {
    let kind: String
    let title: [Inline]
    let inner: [Block]

    var body: some View {
        let style = CalloutStyle(kind: kind)
        VStack(alignment: .leading, spacing: 6) {
            Label {
                InlineTextView(title).fontWeight(.semibold)
            } icon: {
                Image(systemName: style.symbol).foregroundStyle(style.color).accessibilityLabel(Text(verbatim: kind))
            }
            BlockList(blocks: inner)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(style.color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
