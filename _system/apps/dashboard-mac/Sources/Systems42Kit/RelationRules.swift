import Foundation
import Yams

/// The facts the store takes from the wiki's own metamodel, so no folder, prefix
/// or field name of a content type stands in the code (CON-006). `Metamodel` builds it
/// from the pages it has read, so the metamodel is parsed once. It never fails:
/// what it cannot read is missing.
///
/// Two type names stay in the code because the app treats these types specially:
/// `issue` (open issues of a page) and `source` (provenance links).
struct RelationRules: Sendable {
    /// A link from pages of one folder to pages of another, as a relation page declares it.
    struct Edge: Hashable, Sendable {
        let from: String
        let to: String
    }

    struct Relation: Sendable {
        /// The frontmatter field that holds the links.
        let field: String
        let edges: [Edge]
    }

    static let issueType = "issue"
    static let sourceType = "source"

    /// The metamodel does not mark which issue statuses are closed. It lists
    /// `open, in-progress, resolved, wontfix` for the issue lifecycle only. Open debt:
    /// read the closed states once the metamodel marks them.
    static let closedIssueStatuses: Set<String> = ["resolved", "wontfix"]

    /// The keys of a step that name pages. The metamodel names them only in prose
    /// (`rel-steps.md`, `type-runtime-scenario.md`), so they are fixed here. Open debt.
    static let stepLinkKeys: Set<String> = ["from", "to"]

    /// Relation name to relation.
    private(set) var relations: [String: Relation] = [:]
    /// Type name to its folder as the type page writes it, such as `wiki/goals`.
    private(set) var folders: [String: String] = [:]
    /// Type name to its id prefix.
    private(set) var prefixes: [String: String] = [:]

    init() {}

    init(types: [MetaPage], relations pages: [MetaPage]) {
        for page in types {
            guard let name = page.entry.scalar("name") else { continue }
            if let prefix = page.entry.scalar("prefix") { prefixes[name] = prefix }
            if let folder = page.entry.scalar("folder") { folders[name] = folder }
        }
        let wikiFolders = self.wikiFolders
        for page in pages {
            guard let name = page.entry.scalar("name"), let field = page.entry.scalar("field") else { continue }
            let edges: [Edge] = page.entry.entries("edges").compactMap { edge in
                guard let from = edge.scalar("from").flatMap({ wikiFolders[$0] }),
                      let to = edge.scalar("to").flatMap({ wikiFolders[$0] }) else { return nil }
                return Edge(from: from, to: to)
            }
            relations[name] = Relation(field: field, edges: edges)
        }
    }

    /// Type name to the folder inside `wiki/`. Types that live elsewhere are left out.
    var wikiFolders: [String: String] {
        folders.compactMapValues { $0.hasPrefix("wiki/") ? String($0.dropFirst("wiki/".count)) : nil }
    }

    var issueFolder: String? { wikiFolders[Self.issueType] }

    /// The folder of the source records below the root, such as `raw/sources`, and its last part.
    var sourceFolder: (path: String, name: String)? {
        guard let path = folders[Self.sourceType],
              let name = path.split(separator: "/").last.map(String.init) else { return nil }
        return (path, name)
    }

    /// The start of a source id, such as `SRC-`.
    var sourceIdStart: String? { prefixes[Self.sourceType].map { $0 + "-" } }
}
