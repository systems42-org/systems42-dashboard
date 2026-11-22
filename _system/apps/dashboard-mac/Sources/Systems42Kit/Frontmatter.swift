import Foundation
import Yams

/// One frontmatter value, as far as the app tells kinds apart.
public enum FieldValue: Equatable, Sendable {
    /// A scalar. A number, a date or a bool keeps the text as written.
    case text(String)
    /// A list of scalars, nested lists flattened (an unquoted `[[x]]` is a list in a list).
    case list([String])
    /// A list of scalars where at least one holds a wikilink, with all links in order.
    case links([Wikilink])
    /// A mapping, a list holding a mapping, or anything too large to read.
    case other
}

/// What `Frontmatter.read` found in the YAML block of a page.
struct FrontmatterFields {
    var fields: [String: FieldValue] = [:]
    /// Wikilinks inside a scalar, at any depth, per top-level field.
    var links: [String: [Wikilink]] = [:]
    /// Page names a field refers to as the dashboard's trace panel reads them:
    /// the items of a list, bare or linked, and `from`/`to` of a list of mappings.
    var references: [String: [String]] = [:]
    var problems: [String] = []
}

enum Frontmatter {
    struct Split {
        /// The text between the two `---` lines, nil when the page has none.
        var yaml: String?
        var body: String
        var problem: String?
    }

    /// The frontmatter block is the first line `---` up to the next line `---`.
    /// Both lines may carry trailing whitespace. Without a closing line, or
    /// without an opening one, the whole text is the body and `problem` says why.
    static func split(_ text: String) -> Split {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, isFence(first) else {
            return Split(yaml: nil, body: text, problem: text.isEmpty ? "the file is empty" : "no frontmatter")
        }
        guard let end = lines.dropFirst().firstIndex(where: isFence) else {
            return Split(yaml: nil, body: text, problem: "the frontmatter is not closed by a --- line")
        }
        return Split(
            yaml: lines[1..<end].joined(separator: "\n"),
            body: lines[(end + 1)...].joined(separator: "\n"),
            problem: nil
        )
    }

    private static func isFence(_ line: Substring) -> Bool {
        line.hasPrefix("---") && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// Deepest nesting read. Deeper than any real page, and shallow enough for the stack.
    private static let deepest = 32
    /// Most YAML nodes read. A page with aliases that fan out stops here.
    private static let mostNodes = 5_000
    /// Nesting the YAML parser is trusted with, counted before it runs.
    private static let deepestInput = 100

    static func read(_ yaml: String) -> FrontmatterFields {
        var result = FrontmatterFields()
        guard nestingDepth(of: yaml) <= deepestInput else {
            result.problems.append("the frontmatter is nested too deeply")
            return result
        }
        let root: Node?
        do {
            root = try compose(yaml: yaml)
        } catch {
            result.problems.append("the frontmatter is not valid YAML")
            return result
        }
        guard let root else { return result }
        guard case .mapping(let mapping) = root else {
            if root.scalar?.string.isEmpty != true { result.problems.append("the frontmatter is not a mapping") }
            return result
        }
        var budget = mostNodes
        for (key, value) in mapping {
            guard let name = key.scalar?.string else { continue }
            var reader = Reader(budget: budget)
            result.fields[name] = reader.value(of: value)
            if !reader.links.isEmpty { result.links[name] = reader.links }
            let references = reader.references(of: value)
            if !references.isEmpty { result.references[name] = references }
            budget = reader.budget
            if reader.exhausted {
                result.problems.append("the frontmatter is too large, \(name) and later fields are cut off")
                break
            }
        }
        return result
    }

    /// Flow brackets open at once, or leading spaces and `- ` markers on a line.
    /// A rough count: it only has to catch input built to exhaust the stack.
    static func nestingDepth(of yaml: String) -> Int {
        var deepest = 0
        var flow = 0
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            var lead = 0
            var rest = line[...]
            while true {
                if rest.hasPrefix(" ") { lead += 1; rest = rest.dropFirst() }
                else if rest.hasPrefix("- ") { lead += 1; rest = rest.dropFirst(2) }
                else { break }
            }
            deepest = max(deepest, lead + flow)
            for ch in rest.utf8 {
                if ch == UInt8(ascii: "[") || ch == UInt8(ascii: "{") { flow += 1; deepest = max(deepest, lead + flow) }
                else if (ch == UInt8(ascii: "]") || ch == UInt8(ascii: "}")), flow > 0 { flow -= 1 }
            }
        }
        return deepest
    }

    /// Reads one top-level value within a shared node budget.
    private struct Reader {
        var budget: Int
        var links: [Wikilink] = []
        var exhausted = false

        init(budget: Int) { self.budget = budget }

        mutating func value(of node: Node) -> FieldValue {
            switch node {
            case .scalar(let scalar):
                let text = Frontmatter.text(scalar)
                links += Wikilink.all(in: text)
                return .text(text)
            case .sequence:
                var items: [String] = []
                var hasMapping = false
                collect(node, depth: 0, into: &items, hasMapping: &hasMapping)
                if hasMapping || exhausted { return .other }
                let found = items.flatMap(Wikilink.all(in:))
                return found.isEmpty ? .list(items) : .links(found)
            case .mapping, .alias:
                var items: [String] = []
                var hasMapping = false
                collect(node, depth: 0, into: &items, hasMapping: &hasMapping)
                return .other
            }
        }

        /// Walks a node, flattening lists and gathering the strings of scalars
        /// (their links go to `links`).
        private mutating func collect(_ node: Node, depth: Int, into items: inout [String], hasMapping: inout Bool) {
            guard spend(depth: depth) else { return }
            switch node {
            case .scalar(let scalar):
                let text = Frontmatter.text(scalar)
                items.append(text)
                if depth > 0 { links += Wikilink.all(in: text) }
            case .sequence(let sequence):
                for item in sequence { collect(item, depth: depth + 1, into: &items, hasMapping: &hasMapping) }
            case .mapping(let mapping):
                hasMapping = true
                for (_, item) in mapping { collect(item, depth: depth + 1, into: &items, hasMapping: &hasMapping) }
            case .alias:
                hasMapping = true
            }
        }

        private mutating func spend(depth: Int) -> Bool {
            budget -= 1
            if budget < 0 || depth > Frontmatter.deepest { exhausted = true }
            return !exhausted
        }

        /// The names a field points at. Reads lists and, in them, `from` and `to`.
        mutating func references(of node: Node) -> [String] {
            var names: [String] = []
            walkReferences(node, depth: 0, into: &names)
            return names
        }

        private mutating func walkReferences(_ node: Node, depth: Int, into names: inout [String]) {
            guard spend(depth: depth) else { return }
            switch node {
            case .scalar(let scalar):
                let name = Frontmatter.pageName(in: Frontmatter.text(scalar))
                if !name.isEmpty { names.append(name) }
            case .sequence(let sequence):
                for item in sequence {
                    if case .mapping(let mapping) = item {
                        for (key, value) in mapping where key.scalar?.string == "from" || key.scalar?.string == "to" {
                            walkReferences(value, depth: depth + 1, into: &names)
                        }
                    } else {
                        walkReferences(item, depth: depth + 1, into: &names)
                    }
                }
            case .mapping, .alias:
                break
            }
        }
    }

    /// The text of a scalar. A plain `null`, `~` or empty value is "".
    static func text(_ scalar: Node.Scalar) -> String {
        Node.scalar(scalar).null != nil ? "" : scalar.string
    }

    /// The page a frontmatter entry names: the inside of the first `[[...]]`, or the
    /// whole text, cut at `|` and `#`, as the last path component.
    static func pageName(in text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = name.range(of: "[["), let close = name.range(of: "]]", range: open.upperBound..<name.endIndex) {
            name = String(name[open.upperBound..<close.lowerBound])
        }
        if let cut = name.firstIndex(where: { $0 == "|" || $0 == "#" }) { name = String(name[..<cut]) }
        let last = name.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
