import Foundation

/// One field a type page declares for its pages.
public struct MMField: Sendable {
    public let name, kind: String
    public let doc: String?
    public let values: [String]
    public let relation: String?
    public let required: Bool
}

/// A content type as its page in `_system/metamodel/types/` declares it.
public struct MMType: Sendable {
    public let name, prefix, folder, label, block, summary: String
    /// The name of the lifecycle the type's `status` follows, "" when the page names none.
    public let lifecycle: String
    public let fields: [MMField]
    public let anchors, projections, stereotypes: [String]
    public let body: String
}

/// A relation, projection or rule page of the metamodel.
public struct MMConstruct: Sendable {
    public let construct, name, summary, body: String
    public let frontmatter: [String: FieldValue]
}

/// What the wiki's metamodel declares about its own version.
public enum VersionState: Equatable, Sendable {
    case supported(String)
    case unsupported(found: String, supported: [String])
    case missing(supported: [String])
}

/// The metamodel of an open wiki, read from `_system/metamodel/` and `_system/anchors/`.
/// Everything the app knows about content types, sections and standards comes from here (CON-006).
public struct Metamodel: Sendable {
    public static let supportedVersions = ["0.1"]

    public let types: [MMType]
    public let relations, projections, rules: [MMConstruct]
    public let anchors: [Anchor]
    public let sections: [Section]
    /// Lifecycle name to its statuses in order, from `meta-metamodel`.
    public let lifecycles: [String: [String]]
    /// The names of the fields every page has, in the order `meta-metamodel` declares them.
    public let universalFields: [String]
    public let version: VersionState

    let relationRules: RelationRules
    private let typesByName: [String: MMType]
    private let anchorsByName: [String: Anchor]

    /// Reads the metamodel. It never throws: a page it cannot read is left out,
    /// and a missing folder gives an empty metamodel.
    public static func load(_ root: WikiRoot) -> Metamodel {
        load(url: root.url)
    }

    static func load(url: URL) -> Metamodel {
        let folder = "_system/metamodel"
        var all = Files.metaPages(root: url, folder: folder)
        for name in Files.subfolders(root: url, folder: folder) {
            all += Files.metaPages(root: url, folder: folder + "/" + name)
        }
        let metamodelPages = all.filter { $0.entry.scalar("type") == "metamodel" && $0.entry.scalar("name") != nil }
        func pages(of construct: String) -> [MetaPage] {
            metamodelPages.filter { $0.entry.scalar("construct") == construct }
        }

        // A repeated type name keeps its first page everywhere.
        var seenTypes = Set<String>()
        let typePages = pages(of: "type").filter { seenTypes.insert($0.entry.scalar("name") ?? "").inserted }
        let catalog = Catalog.build(frameworks: pages(of: "framework"), types: typePages)
        let blockPosition = Dictionary(catalog.blockIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let types = typePages.map(MMType.init).sorted { a, b in
            let pa = blockPosition[a.block] ?? blockPosition.count, pb = blockPosition[b.block] ?? blockPosition.count
            return pa != pb ? pa < pb : a.name < b.name
        }
        var byName: [String: MMType] = [:]
        for type in types where byName[type.name] == nil { byName[type.name] = type }
        for page in typePages {
            guard let name = page.entry.scalar("name"), let type = byName[name] else { continue }
            for alias in page.entry.strings("aliases") where byName[alias] == nil { byName[alias] = type }
        }
        let anchors = Anchor.read(root: url)

        return Metamodel(
            types: types,
            relations: pages(of: "relation").map { MMConstruct($0, construct: "relation") },
            projections: pages(of: "projection").map { MMConstruct($0, construct: "projection") },
            rules: pages(of: "rule").map { MMConstruct($0, construct: "rule") },
            anchors: anchors,
            sections: catalog.sections,
            lifecycles: readLifecycles(pages(of: "meta-metamodel")),
            universalFields: readUniversalFields(pages(of: "meta-metamodel")),
            version: readVersion(root: url),
            relationRules: RelationRules(types: typePages, relations: pages(of: "relation")),
            typesByName: byName,
            anchorsByName: Anchor.index(anchors)
        )
    }

    /// The statuses, in order, of the lifecycle all types of the section follow.
    /// Nil when the types differ, name none, or the lifecycle is not declared.
    public func lifecycle(of section: Section) -> [String]? {
        let names = Set(section.types.map { typesByName[$0]?.lifecycle ?? "" })
        guard names.count == 1, let name = names.first else { return nil }
        return lifecycles[name]
    }

    /// The type with this name or alias, such as `functional-requirement` or `FR`.
    public func type(named name: String) -> MMType? {
        typesByName[name]
    }

    /// The type whose pages live in this folder, written `wiki/goals` or `goals`.
    public func type(forFolder folder: String) -> MMType? {
        let wanted = folder.split(separator: "/").last
        return types.first { $0.folder == folder || ($0.folder.split(separator: "/").last == wanted && wanted != nil) }
    }

    /// The section whose types include the issue type. Nil when the metamodel has none.
    public var issueSection: Section? {
        sections.first { $0.types.contains(RelationRules.issueType) }
    }

    /// The anchor with this name, title or alias, ignoring case.
    public func anchor(_ nameOrAlias: String) -> Anchor? {
        anchorsByName[nameOrAlias.lowercased()]
    }

    private static func readUniversalFields(_ pages: [MetaPage]) -> [String] {
        var seen = Set<String>()
        return pages.flatMap { $0.entry.entries("universal_fields") }.compactMap { $0.scalar("name") }.filter { seen.insert($0).inserted }
    }

    private static func readLifecycles(_ pages: [MetaPage]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for page in pages {
            guard case .mapping(let map)? = page.entry.node("lifecycles") else { continue }
            for (key, value) in map {
                guard let name = key.scalar?.string, result[name] == nil, case .sequence(let items) = value else { continue }
                result[name] = items.compactMap { $0.scalar.map(Frontmatter.text)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        return result
    }

    /// The version files, in the order they are looked at. The first one that exists decides.
    private static let versionFiles = ["metamodel-version.md", "meta-metamodel.md"]

    private static func readVersion(root: URL) -> VersionState {
        let supported = supportedVersions
        guard let rootReal = Files.realPath(root) else { return .missing(supported: supported) }
        let dir = root.appending(path: "_system/metamodel")
        for file in versionFiles {
            let url = dir.appending(path: file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // The version is read as text, so `0.10` stays `0.10`.
            guard let found = Files.metaPage(url, rootReal: rootReal)?.entry.scalar("version") else {
                return .missing(supported: supported)
            }
            return supported.contains(found) ? .supported(found) : .unsupported(found: found, supported: supported)
        }
        return .missing(supported: supported)
    }
}

extension MMType {
    init(_ page: MetaPage) {
        let entry = page.entry
        self.init(
            name: entry.scalar("name") ?? page.stem,
            prefix: entry.scalar("prefix") ?? "",
            folder: entry.scalar("folder") ?? "",
            label: entry.scalar("label") ?? "",
            block: entry.scalar("block") ?? "",
            summary: MetaText.summary(of: page.body),
            lifecycle: entry.scalar("lifecycle") ?? "",
            fields: entry.entries("fields").compactMap(MMField.init),
            anchors: entry.strings("anchors"),
            projections: entry.strings("projections"),
            stereotypes: entry.strings("stereotypes"),
            body: page.body
        )
    }
}

extension MMField {
    init?(_ entry: Entry) {
        guard let name = entry.scalar("name") else { return nil }
        self.init(
            name: name,
            kind: entry.scalar("kind") ?? "",
            doc: entry.scalar("doc"),
            values: entry.strings("values"),
            relation: entry.scalar("relation"),
            required: entry.scalar("required")?.lowercased() == "true"
        )
    }
}

extension MMConstruct {
    init(_ page: MetaPage, construct: String) {
        self.init(
            construct: construct,
            name: page.entry.scalar("name") ?? page.stem,
            summary: MetaText.summary(of: page.body),
            body: page.body,
            frontmatter: page.fields
        )
    }
}

/// Text taken from the body of a metamodel or anchor page.
enum MetaText {
    private static let heading = "(?m)^#\\s+.*$"
    private static let blankLine = "\\n\\s*\\n"
    private static let noParagraph = ["-", "*", "|", "#"]

    /// The body without its first level one heading.
    static func withoutHeading(_ body: String) -> String {
        guard let range = body.range(of: heading, options: .regularExpression) else { return body }
        return String(body[..<range.lowerBound] + body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first paragraph of the body, after the heading, as one line. Empty when it is a list, table or heading.
    static func summary(of body: String) -> String {
        let text = withoutHeading(body)
        let head = firstParagraph(text) ?? ""
        let trimmed = head.drop { $0.isWhitespace }
        if noParagraph.contains(where: trimmed.hasPrefix) { return "" }
        return oneLine(head)
    }

    /// The first paragraph that is not a quote, list, table, heading or comment.
    static func definition(of body: String) -> String {
        var rest = withoutHeading(body)
        while let paragraph = firstParagraph(rest) {
            let head = paragraph.drop { $0.isWhitespace }
            if !head.isEmpty, !(noParagraph + [">", "<!--"]).contains(where: head.hasPrefix) { return oneLine(paragraph) }
            guard let split = rest.range(of: blankLine, options: .regularExpression) else { break }
            rest = String(rest[split.upperBound...])
        }
        return ""
    }

    private static func firstParagraph(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let split = text.range(of: blankLine, options: .regularExpression) else { return text }
        return String(text[..<split.lowerBound])
    }

    private static func oneLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
