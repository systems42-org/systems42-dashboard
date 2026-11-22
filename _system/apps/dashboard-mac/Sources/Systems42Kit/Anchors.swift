import Foundation

/// A method standard of `_system/anchors/`, such as a goal frame or a prioritization scheme.
public struct Anchor: Sendable {
    /// The file name without `.md`.
    public let name: String
    /// The frontmatter title, else the name.
    public let title: String
    /// The first plain paragraph of the body.
    public let definition: String
    public let aliases, appliesTo: [String]
    /// The first web address in the body.
    public let reference: URL?
    /// The body without its heading.
    public let body: String
}

extension Anchor {
    private static let address = "https?://[^\\s<>()\\]]+"

    /// The anchors of a wiki, sorted by title.
    static func read(root: URL) -> [Anchor] {
        Files.metaPages(root: root, folder: "_system/anchors")
            .filter { $0.entry.scalar("type") == "anchor" }
            .map(Anchor.init)
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    private init(_ page: MetaPage) {
        let body = MetaText.withoutHeading(page.body)
        name = page.stem
        title = page.entry.scalar("title") ?? page.stem
        definition = MetaText.definition(of: page.body)
        aliases = page.entry.strings("aliases")
        appliesTo = page.entry.strings("applies-to")
        reference = body.range(of: Self.address, options: .regularExpression).flatMap {
            URL(string: String(body[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:")))
        }
        self.body = body
    }

    /// Lowercased name, title and aliases mapped to the anchor. The first anchor keeps a clashing key.
    static func index(_ anchors: [Anchor]) -> [String: Anchor] {
        var index: [String: Anchor] = [:]
        for anchor in anchors {
            for key in [anchor.name, anchor.title] + anchor.aliases {
                let key = key.lowercased().trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, index[key] == nil { index[key] = anchor }
            }
        }
        return index
    }
}
