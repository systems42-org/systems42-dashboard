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

/// A page name a field refers to. `key` is the key of the mapping the name stood in, nil for a list item.
struct Reference: Equatable, Sendable {
    let key: String?
    let name: String
}

/// What `Frontmatter.read` found in the YAML block of a page.
struct FrontmatterFields {
    var fields: [String: FieldValue] = [:]
    /// Wikilinks inside a scalar, at any depth, per top-level field.
    var links: [String: [Wikilink]] = [:]
    /// Page names a field refers to as the dashboard's trace panel reads them:
    /// the items of a list, bare or linked, and the values of a list of mappings
    /// (the `from` and `to` of a step). A value that names no page is dropped later.
    var references: [String: [Reference]] = [:]
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
    static let deepestInput = 100

    /// The top-level mapping of a YAML block. Nil when the block is empty, too deeply
    /// nested, not valid YAML or not a mapping, and `problems` then says why (an empty block says nothing).
    static func mapping(of yaml: String, problems: inout [String]) -> Node.Mapping? {
        guard nestingDepth(of: yaml) <= deepestInput else {
            problems.append("the frontmatter is nested too deeply")
            return nil
        }
        let root: Node?
        do {
            root = try compose(yaml: yaml)
        } catch {
            problems.append("the frontmatter is not valid YAML")
            return nil
        }
        guard let root else { return nil }
        guard case .mapping(let mapping) = root else {
            if root.scalar?.string.isEmpty != true { problems.append("the frontmatter is not a mapping") }
            return nil
        }
        return mapping
    }

    static func read(_ yaml: String) -> FrontmatterFields {
        var problems: [String] = []
        let parsed = mapping(of: yaml, problems: &problems)
        var result = parsed.map(read(mapping:)) ?? FrontmatterFields()
        result.problems = problems + result.problems
        return result
    }

    static func read(mapping: Node.Mapping) -> FrontmatterFields {
        var result = FrontmatterFields()
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
                result.problems.append("the frontmatter is too large: \(name) and later fields are cut off")
                break
            }
        }
        return result
    }

    /// How deep the YAML nests: indentation levels, `- ` markers and open flow brackets
    /// (`[` and `{`). Quoted text, comments and a `[` inside a plain word are not counted,
    /// and a key at column 0 closes any flow brackets left open. A rough count: it only has
    /// to catch input built to exhaust the stack. Indentation counts levels, not spaces,
    /// so a deeply indented block scalar is one level.
    static func nestingDepth(of yaml: String) -> Int {
        var deepest = 0
        var flow = 0
        var indents: [Int] = []
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = line[...]
            var spaces = 0
            while rest.hasPrefix(" ") { spaces += 1; rest = rest.dropFirst() }
            if rest.isEmpty || rest.hasPrefix("#") { continue }
            while let last = indents.last, last > spaces { indents.removeLast() }
            if indents.last != spaces { indents.append(spaces) }
            var dashes = 0
            while rest.hasPrefix("- ") {
                dashes += 1
                rest = rest.dropFirst(2)
                while rest.hasPrefix(" ") { rest = rest.dropFirst() }
            }
            if spaces == 0, flow > 0, startsWithKey(rest) { flow = 0 }
            deepest = max(deepest, indents.count + dashes + flow)
            var quote: UInt8?
            var previous: UInt8?
            var escaped = false
            var wasSpace = false
            scan: for byte in rest.utf8 {
                if let open = quote {
                    if escaped { escaped = false }
                    else if byte == UInt8(ascii: "\\"), open == UInt8(ascii: "\"") { escaped = true }
                    else if byte == open { quote = nil; previous = byte }
                    continue
                }
                let startsValue = previous == nil || ":-,[{".utf8.contains(previous!)
                switch byte {
                case UInt8(ascii: "#") where wasSpace:
                    break scan
                case UInt8(ascii: "\""), UInt8(ascii: "'"):
                    if startsValue { quote = byte } else { previous = byte }
                case UInt8(ascii: "["), UInt8(ascii: "{"):
                    if startsValue { flow += 1; deepest = max(deepest, indents.count + dashes + flow) }
                    previous = byte
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    if flow > 0 { flow -= 1 }
                    previous = byte
                case UInt8(ascii: " "):
                    break
                default:
                    previous = byte
                }
                wasSpace = byte == UInt8(ascii: " ")
            }
        }
        return deepest
    }

    /// A line such as `title: x` or `parent:`, the start of a new top-level field.
    private static func startsWithKey(_ line: Substring) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        return colon != line.startIndex && line[..<colon].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
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

        /// The names a field points at. Reads lists and the values of mappings in them.
        mutating func references(of node: Node) -> [Reference] {
            var found: [Reference] = []
            walkReferences(node, key: nil, depth: 0, into: &found)
            return found
        }

        private mutating func walkReferences(_ node: Node, key: String?, depth: Int, into found: inout [Reference]) {
            guard spend(depth: depth) else { return }
            switch node {
            case .scalar(let scalar):
                let name = Frontmatter.pageName(in: Frontmatter.text(scalar))
                if !name.isEmpty { found.append(Reference(key: key, name: name)) }
            case .sequence(let sequence):
                for item in sequence {
                    if case .mapping(let mapping) = item {
                        for (entryKey, value) in mapping {
                            walkReferences(value, key: entryKey.scalar?.string ?? "", depth: depth + 1, into: &found)
                        }
                    } else {
                        walkReferences(item, key: key, depth: depth + 1, into: &found)
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
