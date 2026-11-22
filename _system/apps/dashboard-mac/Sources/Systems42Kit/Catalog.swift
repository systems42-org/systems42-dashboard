import Foundation

/// The three areas of the sidebar. They are the only fixed names: a framework page
/// names its area with one of these keys, and every section comes from the metamodel.
public enum Area: String, CaseIterable, Sendable {
    case requirements, architecture, commons
}

/// One framework block of the metamodel, as the sidebar shows it.
public struct Section: Identifiable, Sendable {
    public let id, title, scope: String
    public let area: Area
    /// The folders below `wiki/` that hold its pages, from the types the block lists.
    public let folders: [String]
    /// The type names the block lists.
    public let types: [String]
}

/// Sections built from the framework pages of the metamodel (FR-044, FR-023).
struct Catalog {
    var sections: [Section] = []
    /// Block ids in section order, the order the types are listed in.
    var blockIds: [String] { sections.map(\.id) }

    /// A block with no scope is `in`. A block that repeats an id, or sits in a framework with
    /// an unknown area, is left out. Sections are grouped by area, blocks stay in file order.
    static func build(frameworks: [MetaPage], types: [MetaPage]) -> Catalog {
        var folderOf: [String: String] = [:]
        for page in types {
            guard let name = page.entry.scalar("name"),
                  let folder = page.entry.scalar("folder")?.split(separator: "/").last else { continue }
            folderOf[name] = String(folder)
        }
        var catalog = Catalog()
        var seen = Set<String>()
        for framework in frameworks {
            guard let area = framework.entry.scalar("area").flatMap(Area.init(rawValue:)) else { continue }
            for block in framework.entry.entries("blocks") {
                guard let id = block.scalar("id"), seen.insert(id).inserted else { continue }
                let typeNames = block.strings("types")
                catalog.sections.append(Section(
                    id: id,
                    title: block.scalar("title") ?? id,
                    scope: block.scalar("scope") ?? "in",
                    area: area,
                    folders: typeNames.compactMap { folderOf[$0] },
                    types: typeNames
                ))
            }
        }
        let rank = Dictionary(uniqueKeysWithValues: Area.allCases.enumerated().map { ($1, $0) })
        // sorted(by:) is not stable, so the file order rides along.
        catalog.sections = catalog.sections.enumerated()
            .sorted { (rank[$0.element.area]!, $0.offset) < (rank[$1.element.area]!, $1.offset) }
            .map(\.element)
        return catalog
    }
}
