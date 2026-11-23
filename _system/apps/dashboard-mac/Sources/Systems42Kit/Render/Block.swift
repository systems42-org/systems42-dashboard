import Foundation

/// Text inside a block. There is no case for HTML: raw HTML in a page is text.
public indirect enum Inline: Equatable, Sendable {
    case text(String), code(String), emphasis([Inline]), strong([Inline])
    /// A wikilink, already resolved. The label is the text to show, `raw` the link target as written.
    case link([Inline], LinkTarget, raw: String)
    /// An outside link. The scheme is `http`, `https` or `mailto` and nothing else.
    case url([Inline], URL)
}

/// What the page column draws.
public indirect enum Block: Equatable, Sendable {
    case heading(level: Int, [Inline]), paragraph([Inline])
    case list(ordered: Bool, items: [[Block]])
    case table(header: [[Inline]], rows: [[[Inline]]])
    case code(language: String?, String)
    /// `> [!note] Title`. The kind is lowercase.
    case callout(kind: String, title: [Inline], [Block])
    case quote([Block]), rule
    /// A `mermaid` code block.
    case diagram(language: String, String)
}

/// A page body as blocks, and the formats it says it follows (`> follows [[MADR]]`).
public struct RenderedPage: Equatable, Sendable {
    public let follows: [String]
    public let blocks: [Block]
    /// Why the page is not formatted, in plain words. Empty for a sound page.
    public let problems: [String]

    public init(follows: [String], blocks: [Block], problems: [String] = []) {
        self.follows = follows
        self.blocks = blocks
        self.problems = problems
    }
}
