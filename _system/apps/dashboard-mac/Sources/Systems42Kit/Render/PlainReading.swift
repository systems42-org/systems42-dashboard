import Foundation

/// The page for a reader who wants no links (FR-049): every link shows only its
/// text. Emphasis, code and structure stay.
public func plainReading(_ page: RenderedPage) -> RenderedPage {
    RenderedPage(follows: page.follows, blocks: page.blocks.map(plain), problems: page.problems)
}

private func plain(_ block: Block) -> Block {
    switch block {
    case .heading(let level, let inlines): .heading(level: level, plain(inlines))
    case .paragraph(let inlines): .paragraph(plain(inlines))
    case .list(let ordered, let items): .list(ordered: ordered, items: items.map { $0.map(plain) })
    case .table(let header, let rows): .table(header: header.map(plain), rows: rows.map { $0.map(plain) })
    case .callout(let kind, let title, let inner): .callout(kind: kind, title: plain(title), inner.map(plain))
    case .quote(let inner): .quote(inner.map(plain))
    case .code, .rule, .diagram: block
    }
}

private func plain(_ inlines: [Inline]) -> [Inline] {
    var out: [Inline] = []
    for inline in inlines {
        switch inline {
        case .link(let label, _, _), .url(let label, _): out.append(contentsOf: plain(label))
        case .emphasis(let inner): out.append(.emphasis(plain(inner)))
        case .strong(let inner): out.append(.strong(plain(inner)))
        case .text, .code: out.append(inline)
        }
    }
    return merged(out)
}

/// Joins neighbouring text, so a flattened link reads as part of its sentence.
func merged(_ inlines: [Inline]) -> [Inline] {
    var out: [Inline] = []
    for inline in inlines {
        if case .text(let more) = inline, case .text(let before)? = out.last {
            out[out.count - 1] = .text(before + more)
        } else {
            out.append(inline)
        }
    }
    return out
}
