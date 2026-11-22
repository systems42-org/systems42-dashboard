import Foundation

/// Where a page lives: `wiki/<folder>/<stem>.md`.
public struct PageRef: Hashable, Sendable {
    public let folder: String
    public let stem: String

    public init(folder: String, stem: String) {
        self.folder = folder
        self.stem = stem
    }

    /// A ref that names a file inside one folder of the wiki and nothing else:
    /// no empty or dotted names, no separators, no control characters.
    var isSafe: Bool {
        Self.isSafeName(folder) && Self.isSafeName(stem) && !folder.hasPrefix(".")
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.unicodeScalars.contains { $0 == "/" || $0 == "\\" || $0.value < 0x20 || $0.value == 0x7F }
    }
}

/// The universal fields the code needs a meaning for. `meta-metamodel` lists the universal fields
/// (`Metamodel.universalFields`) but does not say which one is the id, the title or the status.
public enum PageKey {
    public static let id = "id", title = "title", status = "status"
}

/// One wiki page. A page that could not be read fully still exists: its
/// `problems` say what went wrong, and `id` and `title` fall back to the stem.
public struct Page: Identifiable, Sendable {
    public let ref: PageRef
    /// Frontmatter `id`, else the stem.
    public let id: String
    /// Frontmatter `type`, else "".
    public let type: String
    /// Frontmatter `title`, else the stem.
    public let title: String
    public let status: String
    public let fields: [String: FieldValue]
    /// Markdown without the frontmatter.
    public let body: String
    /// What could not be read, in plain words. Empty for a sound page.
    public internal(set) var problems: [String]
    /// The wikilinks inside each top-level field, at any depth.
    public let fieldLinks: [String: [Wikilink]]
    /// The wikilinks in the body.
    public let bodyLinks: [Wikilink]
    /// What a field points at, for the trace of an architecture page.
    let references: [String: [Reference]]
    let aliases: [String]

    init(ref: PageRef, text: String, readProblems: [String] = [], checksFrontmatter: Bool = true) {
        let split = Frontmatter.split(text)
        let read = split.yaml.map(Frontmatter.read) ?? FrontmatterFields()
        var problems = readProblems + (checksFrontmatter ? [split.problem].compactMap { $0 } : []) + read.problems

        func scalar(_ key: String) -> String {
            switch read.fields[key] {
            case .text(let value):
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            case nil:
                return ""
            default:
                problems.append("\(key) is not text")
                return ""
            }
        }
        let id = scalar(PageKey.id)
        let title = scalar(PageKey.title)
        self.ref = ref
        self.id = id.isEmpty ? ref.stem : id
        self.type = scalar("type")
        self.title = title.isEmpty ? ref.stem : title
        self.status = scalar(PageKey.status)
        self.fields = read.fields
        self.body = split.body
        self.problems = problems
        self.fieldLinks = read.links
        self.bodyLinks = Wikilink.all(in: split.body)
        self.references = read.references
        switch read.fields["aliases"] {
        case .list(let items)?: self.aliases = items.filter { !$0.isEmpty }
        case .text(let item)?: self.aliases = item.isEmpty ? [] : [item]
        default: self.aliases = []
        }
    }

    /// A page for a file that could not be read at all.
    init(unreadable ref: PageRef, because problem: String) {
        self.init(ref: ref, text: "", readProblems: [problem], checksFrontmatter: false)
    }
}
