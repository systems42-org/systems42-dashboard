import Foundation
import Yams

/// The facts the store takes from the wiki's own metamodel, so no folder, prefix
/// or field name of a content type stands in the code (CON-006). It reads frontmatter
/// of `_system/metamodel/types/type-*.md` (`name`, `prefix`, `folder`) and
/// `_system/metamodel/relations/rel-*.md` (`field`, `edges`). It never throws:
/// what it cannot read is missing. The full metamodel reader comes later and may absorb this.
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

    /// Relation name to relation.
    private(set) var relations: [String: Relation] = [:]
    /// Type name to the folder inside `wiki/`.
    private(set) var wikiFolders: [String: String] = [:]
    /// Type name to its id prefix, such as `SRC`.
    private(set) var prefixes: [String: String] = [:]

    var issueFolder: String? { wikiFolders[Self.issueType] }

    /// The start of a source id, such as `SRC-`.
    var sourceIdStart: String? { prefixes[Self.sourceType].map { $0 + "-" } }

    private static let mostEdges = 2_000

    static func read(root: URL) -> RelationRules {
        var rules = RelationRules()
        var typeFolders: [String: String] = [:]
        for entry in Files.frontmatter(root: root, folder: "_system/metamodel/types", prefix: "type-") {
            guard let name = entry.scalar("name") else { continue }
            if let prefix = entry.scalar("prefix") { rules.prefixes[name] = prefix }
            if let folder = entry.scalar("folder"), folder.hasPrefix("wiki/") {
                typeFolders[name] = String(folder.dropFirst("wiki/".count))
            }
        }
        rules.wikiFolders = typeFolders
        for entry in Files.frontmatter(root: root, folder: "_system/metamodel/relations", prefix: "rel-") {
            guard let name = entry.scalar("name"), let field = entry.scalar("field") else { continue }
            var edges: [Edge] = []
            if case .sequence(let items)? = entry.node("edges") {
                for item in items.prefix(mostEdges) {
                    guard case .mapping(let mapping) = item,
                          let from = Entry(mapping: mapping).scalar("from").flatMap({ typeFolders[$0] }),
                          let to = Entry(mapping: mapping).scalar("to").flatMap({ typeFolders[$0] }) else { continue }
                    edges.append(Edge(from: from, to: to))
                }
            }
            rules.relations[name] = Relation(field: field, edges: edges)
        }
        return rules
    }

    /// The top-level keys of one frontmatter block.
    struct Entry {
        let mapping: Node.Mapping

        func node(_ key: String) -> Node? {
            mapping.first { $0.key.scalar?.string == key }?.value
        }

        func scalar(_ key: String) -> String? {
            guard let scalar = node(key)?.scalar else { return nil }
            let text = Frontmatter.text(scalar)
            return text.isEmpty ? nil : text
        }
    }
}
