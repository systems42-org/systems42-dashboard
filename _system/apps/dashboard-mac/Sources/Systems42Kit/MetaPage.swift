import Foundation
import Yams

/// The top-level keys of one frontmatter block, read from the parsed YAML.
struct Entry {
    let mapping: Node.Mapping

    /// Most items read from one list, so a page cannot fan out.
    static let mostItems = 2_000

    func node(_ key: String) -> Node? {
        mapping.first { $0.key.scalar?.string == key }?.value
    }

    /// The text of a scalar. Nil when the key is missing, empty, null or not a scalar.
    func scalar(_ key: String) -> String? {
        guard let scalar = node(key)?.scalar else { return nil }
        let text = Frontmatter.text(scalar).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The scalars of a list, or the one scalar as a list of one. Items that are not scalars are left out.
    func strings(_ key: String) -> [String] {
        switch node(key) {
        case .scalar(let scalar)?:
            let text = Frontmatter.text(scalar).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [text]
        case .sequence(let items)?:
            return items.prefix(Self.mostItems).compactMap { item in
                guard let scalar = item.scalar else { return nil }
                let text = Frontmatter.text(scalar).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        default:
            return []
        }
    }

    /// Every top-level list of mappings, by key, each mapping as its scalar values in text.
    var records: [String: [[String: String]]] {
        var result: [String: [[String: String]]] = [:]
        for (key, value) in mapping {
            guard let name = key.scalar?.string, case .sequence(let items) = value else { continue }
            let list: [[String: String]] = items.prefix(Self.mostItems).compactMap { item in
                guard case .mapping(let map) = item else { return nil }
                var record: [String: String] = [:]
                for (field, node) in map {
                    guard let fieldName = field.scalar?.string else { continue }
                    if let scalar = node.scalar {
                        record[fieldName] = Frontmatter.text(scalar).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if case .sequence(let values) = node {
                        // A list of scalars is kept as its items joined by a comma.
                        record[fieldName] = values.compactMap { $0.scalar.map(Frontmatter.text) }.joined(separator: ",")
                    }
                }
                return record
            }
            if !list.isEmpty { result[name] = list }
        }
        return result
    }

    /// The mappings of a list. Items that are not mappings are left out.
    func entries(_ key: String) -> [Entry] {
        guard case .sequence(let items)? = node(key) else { return [] }
        return items.prefix(Self.mostItems).compactMap { item in
            guard case .mapping(let mapping) = item else { return nil }
            return Entry(mapping: mapping)
        }
    }
}

/// One page of `_system/metamodel/` or `_system/anchors/`: its frontmatter and its body.
struct MetaPage {
    /// The file name without `.md`.
    let stem: String
    let entry: Entry
    let fields: [String: FieldValue]
    /// The body, trimmed.
    let body: String
}

extension Files {
    private static let metaPageLimit = 1024 * 1024

    /// One page whose file resolves inside the root. Nil when the file is not a regular file,
    /// is too large, or has no frontmatter that is a mapping.
    static func metaPage(_ url: URL, rootReal: String) -> MetaPage? {
        guard let real = realPath(url), isInside(real, rootReal), regularFile(real) != nil,
              case .text(let text, _) = read(real, limit: metaPageLimit) else { return nil }
        let split = Frontmatter.split(text)
        var problems: [String] = []
        guard let yaml = split.yaml, let mapping = Frontmatter.mapping(of: yaml, problems: &problems) else { return nil }
        return MetaPage(
            stem: url.deletingPathExtension().lastPathComponent,
            entry: Entry(mapping: mapping),
            fields: Frontmatter.read(mapping: mapping).fields,
            body: split.body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The pages of the `.md` files directly in one folder below the root, in file name order.
    /// Empty when the folder is missing or leads out of the root.
    static func metaPages(root: URL, folder: String) -> [MetaPage] {
        let dir = root.appending(path: folder)
        guard let rootReal = realPath(root), let dirReal = realPath(dir), isInside(dirReal, rootReal) else { return [] }
        return names(in: dir).filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .compactMap { metaPage(dir.appending(path: $0), rootReal: rootReal) }
    }

    /// The names of the visible folders inside one folder below the root, sorted.
    static func subfolders(root: URL, folder: String) -> [String] {
        let dir = root.appending(path: folder)
        guard let rootReal = realPath(root), let dirReal = realPath(dir), isInside(dirReal, rootReal) else { return [] }
        return names(in: dir).filter { !$0.hasPrefix(".") && isFolder(dir.appending(path: $0), inside: rootReal) }
    }
}
