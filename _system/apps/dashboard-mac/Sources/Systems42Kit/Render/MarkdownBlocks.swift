import Foundation
import Markdown

/// Turns the Markdown body of a page into blocks. Reads no file and opens no URL.
///
/// `resolve` tells what a wikilink points at, `title` what to show for a link without a label.
/// Both run on the calling thread, in one pass after parsing, so a closure that needs the main
/// actor is safe. Parsing runs on a worker thread with a large stack and sees only text.
/// Page text never becomes anything but these values: raw HTML is text, and a link
/// is an outside link only with the scheme `http`, `https` or `mailto`.
///
/// A page nested more deeply than the parser's stack allows (see `nestingBound`) is returned as
/// one code block with a problem. Its follows notes are still read.
public func renderPage(
    _ body: String,
    resolve: (Wikilink) -> LinkTarget,
    title: (LinkTarget) -> String?
) -> RenderedPage {
    var follows = Follows()
    let text = follows.dropNotes(from: withLineFeeds(body))
    guard nestingBound(text) <= maxNesting else {
        return RenderedPage(follows: follows.labels, blocks: [.code(language: nil, text)], problems: [tooDeepProblem])
    }
    let start = follows
    let parsed = StackWorker.shared.run { parsePage(text, follows: start) }
    let blocks = withoutActuallyEscaping(resolve) { resolve in
        withoutActuallyEscaping(title) { title in
            let resolver = LinkResolver(links: parsed.links, resolve: resolve, title: title)
            return parsed.blocks.map { resolver.block($0) }
        }
    }
    return RenderedPage(follows: parsed.follows, blocks: blocks, problems: [])
}

/// The parser ends a line at `\n`, `\r` and `\r\n`. The bound and the table step count lines
/// by `\n`, so every line ending becomes one. Other characters are no line ends to the parser:
/// form feed and vertical tab are no indent, U+2028 and U+2029 are ordinary text, NUL is replaced.
func withLineFeeds(_ text: String) -> String {
    guard text.utf8.contains(UInt8(ascii: "\r")) else { return text }
    return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
}

let tooDeepProblem = "This page is nested too deeply to format. It is shown as plain text."

/// The most `nestingBound` allows. Measured in a debug build, the worst vector (lists by indent) costs
/// about 3.5 KB of stack per counted unit, so 10,000 take 35 MB of the worker's 128 MB.
/// The live wiki's highest bound is 151.
let maxNesting = 10_000

/// An upper bound on how deep the parser's tree can get, counted in one pass over the text.
/// It never counts less than the real depth, because every level of every nesting construct
/// needs at least one counted character of its own:
/// - block quote: one `>` per level. Lazy continuation continues a quote, it opens none.
/// - list item: one marker per level, `-`, `+`, `*`, or digits with `.` or `)`. A marker sits in the
///   leading run of its line, which holds nothing but spaces, tabs, `>` and other markers.
///   Counted are `-`, `+`, `.`, `)` there. A `*` is counted everywhere, the digits are not needed.
/// - emphasis and strong emphasis: one or two `*` or `_` per level.
/// - strikethrough: `~` per level.
/// - link and image: a `[` per level (an image is `![`). A reference form uses `[` as well.
/// - Not nesting: code, HTML, autolinks, headings, tables (their cells hold inlines, counted above),
///   thematic breaks, entities.
/// The sum over the whole document is at least the maximum over any path, so no
/// per-paragraph reasoning is needed. It is also a loose bound: it grows with page length.
func nestingBound(_ text: String) -> Int {
    var count = 0
    var inLeadingRun = true
    for byte in text.utf8 {
        switch byte {
        case UInt8(ascii: "\n"):
            inLeadingRun = true
        case UInt8(ascii: "*"), UInt8(ascii: ">"):
            count += 1
        case UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "["):
            count += 1
            inLeadingRun = false
        case UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."), UInt8(ascii: ")"):
            if inLeadingRun { count += 1 }
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            break
        default:
            inLeadingRun = false
        }
    }
    return count
}

/// What the worker hands back: blocks whose wikilinks are still to resolve. Each such link is an
/// `.link([], .missing, raw: "<index>")` that points into `links`.
struct ParsedPage: Sendable {
    let follows: [String]
    let blocks: [Block]
    let links: [PendingLink]
}

struct PendingLink: Sendable {
    let link: Wikilink
    /// In the label of an outside link a wikilink is only text.
    let plain: Bool
}

/// Parses and converts. Runs on the worker and sees no closure of the caller.
func parsePage(_ text: String, follows: Follows) -> ParsedPage {
    let renderer = PageRenderer(follows: follows)
    var document = Document(parsing: text)
    if let fixed = escapingWikilinkPipes(in: text, document: document) {
        document = Document(parsing: fixed)
    }
    let blocks = renderer.blocks(of: document, depth: 0)
    return ParsedPage(follows: renderer.follows.labels, blocks: blocks, links: renderer.links)
}

/// Resolves the pending links of a block tree, on the calling thread. The tree is capped in
/// depth already, so this needs no large stack.
private struct LinkResolver {
    let links: [PendingLink]
    let resolve: (Wikilink) -> LinkTarget
    let title: (LinkTarget) -> String?

    func block(_ block: Block) -> Block {
        switch block {
        case .heading(let level, let inlines): .heading(level: level, self.inlines(inlines))
        case .paragraph(let inlines): .paragraph(self.inlines(inlines))
        case .list(let ordered, let items): .list(ordered: ordered, items: items.map { $0.map { self.block($0) } })
        case .table(let header, let rows):
            .table(header: header.map { self.inlines($0) }, rows: rows.map { $0.map { self.inlines($0) } })
        case .callout(let kind, let title, let inner): .callout(kind: kind, title: inlines(title), inner.map { self.block($0) })
        case .quote(let inner): .quote(inner.map { self.block($0) })
        case .code, .rule, .diagram: block
        }
    }

    func inlines(_ inlines: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for inline in inlines {
            switch inline {
            case .link(_, _, let raw):
                let pending = links[Int(raw)!]
                let target = resolve(pending.link)
                let shown = pending.link.label ?? title(target) ?? pending.link.name
                out.append(pending.plain ? .text(shown) : .link([.text(shown)], target, raw: pending.link.target))
            case .emphasis(let inner): out.append(.emphasis(self.inlines(inner)))
            case .strong(let inner): out.append(.strong(self.inlines(inner)))
            case .url(let label, let url): out.append(.url(self.inlines(label), url))
            case .text, .code: out.append(inline)
            }
        }
        return merged(out)
    }
}

/// A pipe inside `[[target|label]]` splits a table cell. Go replaces wikilinks before parsing, so
/// there the cell stays whole. Here, `\|` on the lines of tables, and of paragraphs of
/// several lines (a table whose header row the pipes broke is no table yet), keeps it whole. The text of
/// the link is the same afterwards, and `Wikilink` reads `[[a\|b]]` as target `a`, label `b`.
/// Returns nil when nothing needs escaping.
private func escapingWikilinkPipes(in source: String, document: Document) -> String? {
    let bytes = Array(source.utf8)
    let needsEscape = Wikilink.matches(in: source).contains { match in
        match.utf8Range.contains { bytes[$0] == UInt8(ascii: "|") && bytes[$0 - 1] != UInt8(ascii: "\\") }
    }
    guard needsEscape else { return nil }
    var lines: Set<Int> = []
    var codeSafe: Set<Int> = []  // lines of a plain paragraph, where a backtick may open code
    var stack: [Markup] = [document]
    while let node = stack.popLast() {
        if node is Table || node is Paragraph, let range = node.range {
            if node is Table || range.upperBound.line > range.lowerBound.line {
                for line in range.lowerBound.line...range.upperBound.line {
                    lines.insert(line)
                    if node is Paragraph { codeSafe.insert(line) }
                }
            }
        }
        if !(node is Table || node is Paragraph) { stack.append(contentsOf: node.children) }
    }
    guard !lines.isEmpty else { return nil }
    var all = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var changed = false
    for number in lines where number >= 1 && number <= all.count {
        let bytes = Array(all[number - 1].utf8)
        var out: [UInt8] = []
        var position = 0
        for match in Wikilink.matches(in: all[number - 1]) {
            let range = match.utf8Range
            if codeSafe.contains(number), bytes[..<range.lowerBound].filter({ $0 == UInt8(ascii: "`") }).count % 2 == 1 {
                continue  // inside a code span, a backslash would show
            }
            out += bytes[position..<range.lowerBound]
            for index in range {
                if bytes[index] == UInt8(ascii: "|"), bytes[index - 1] != UInt8(ascii: "\\") {
                    out.append(UInt8(ascii: "\\")); changed = true
                }
                out.append(bytes[index])
            }
            position = range.upperBound
        }
        out += bytes[position...]
        all[number - 1] = String(decoding: out, as: UTF8.self)
    }
    return changed ? all.joined(separator: "\n") : nil
}

/// One thread with a large stack. The parser recurses once or more per nesting level, and a
/// thread of a caller has 512 KB or 8 MB. Callers wait, so one job runs at a time. A job holds
/// no closure of a caller: it takes a string and gives back `Sendable` values.
final class StackWorker: @unchecked Sendable {
    static let shared = StackWorker()
    static let stackSize = 128 << 20

    private final class Box<T>: @unchecked Sendable { var value: T? }

    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private let done = DispatchSemaphore(value: 0)
    private var job: (@Sendable () -> Void)?

    private init() {
        let thread = Thread { [self] in loop() }
        thread.stackSize = Self.stackSize
        thread.qualityOfService = .userInitiated  // a caller on the main thread waits for it
        thread.name = "Systems42 page renderer"
        thread.start()
    }

    private func loop() {
        while true {
            wake.wait()
            do {
                let work = job
                job = nil
                work?()
            }
            done.signal()
        }
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) -> T {
        let box = Box<T>()
        lock.lock()
        job = { box.value = work() }
        wake.signal()
        done.wait()
        lock.unlock()
        return box.value!
    }
}

/// One line of Markdown, such as a page title, as inlines. Text that is more
/// than one paragraph or heading stays literal.
public func renderInline(
    _ text: String,
    resolve: (Wikilink) -> LinkTarget,
    title: (LinkTarget) -> String?
) -> [Inline] {
    let page = renderPage(text, resolve: resolve, title: title)
    guard page.problems.isEmpty else { return [.text(text)] }
    switch page.blocks.first {
    case .paragraph(let inlines)?, .heading(_, let inlines)?:
        if page.blocks.count == 1 { return inlines }
    default:
        break
    }
    return [.text(text)]
}

/// The formats a page says it follows (FR-035), in order, without duplicates.
struct Follows: Sendable {
    private(set) var labels: [String] = []
    private var seen: Set<String> = []

    mutating func add(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted { labels.append(trimmed) }
    }

    /// Removes `> follows ...` notes outside fenced code (FR-035). The fence rule is the Go
    /// dashboard's. A note without a link and with more than 6 words or any of `.!?;:` is an
    /// ordinary quote and stays.
    mutating func dropNotes(from body: String) -> String {
        guard body.contains("follows") else { return body }
        var kept: [Substring] = []
        var fence: (char: Character, length: Int)?
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if let open = Self.fence(of: line) {
                if let current = fence {
                    if open.char == current.char, open.length >= current.length { fence = nil }
                } else {
                    fence = open
                }
                kept.append(line)
            } else if fence == nil, let note = Self.followsNote(line), takeNote(note) {
                continue
            } else {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }

    /// Adds the formats of a follows note. False for text that is an ordinary quote.
    private mutating func takeNote(_ note: String) -> Bool {
        let links = Wikilink.all(in: note)
        if links.isEmpty {
            if note.split(whereSeparator: \.isWhitespace).count > 6 || note.contains(where: { ".!?;:".contains($0) }) {
                return false
            }
            add(Self.withoutLeadingThe(note))
        } else {
            links.forEach { add($0.name) }
        }
        return true
    }

    private static func fence(of line: Substring) -> (char: Character, length: Int)? {
        let rest = line.drop { $0 == " " }
        guard line.count - rest.count <= 3, let first = rest.first, first == "`" || first == "~" else { return nil }
        let run = rest.prefix { $0 == first }.count
        return run >= 3 ? (first, run) : nil
    }

    /// The text after `> follows` of a line, or nil when the line is no such note.
    private static func followsNote(_ line: Substring) -> String? {
        var rest = line.drop { $0 == " " }
        guard line.count - rest.count <= 3, rest.first == ">" else { return nil }
        rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" }
        guard rest.hasPrefix("follows") else { return nil }
        rest = rest.dropFirst(7)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let note = rest.trimmingCharacters(in: .whitespaces)
        return note.isEmpty ? nil : note
    }

    /// Go's `^the\s+`, case-insensitive. Parentheses stay: `(the X)` keeps its `(the`.
    private static func withoutLeadingThe(_ note: String) -> String {
        guard note.lowercased().hasPrefix("the"), note.dropFirst(3).first?.isWhitespace == true else { return note }
        return String(note.dropFirst(3).drop { $0.isWhitespace })
    }

    /// `<!-- follows [[Q42]], https://... -->`: the links are formats the page follows.
    mutating func takeComment(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"), trimmed.count >= 7 else { return false }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.hasPrefix("follows"), inner.dropFirst(7).first.map(\.isWhitespace) ?? true else { return false }
        Wikilink.all(in: inner).forEach { add($0.name) }
        return true
    }
}

private let maxBlockDepth = 10
private let maxInlineDepth = 32

private final class PageRenderer {
    var follows: Follows
    private(set) var links: [PendingLink] = []

    init(follows: Follows) { self.follows = follows }

    // MARK: blocks

    func blocks(of parent: Markup, depth: Int) -> [Block] {
        var out: [Block] = []
        for child in parent.children { block(child, depth: depth, into: &out) }
        return out
    }

    private func block(_ node: Markup, depth: Int, into out: inout [Block]) {
        switch node {
        case let heading as Heading:
            out.append(.heading(level: heading.level, inlines(of: heading.children)))
        case let paragraph as Paragraph:
            out.append(.paragraph(inlines(of: paragraph.children)))
        case let code as CodeBlock:
            out.append(codeBlock(code))
        case is ThematicBreak:
            out.append(.rule)
        case let html as HTMLBlock:
            if !follows.takeComment(html.rawHTML) {
                out.append(.paragraph([.text(html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))]))
            }
        case let table as Table:
            out.append(.table(
                header: table.head.cells.map { inlines(of: $0.children) },
                rows: table.body.rows.map { row in row.cells.map { inlines(of: $0.children) } }
            ))
        case is BlockQuote where depth >= maxBlockDepth, is ListItemContainer where depth >= maxBlockDepth:
            flatten(node, into: &out)
        case let quote as BlockQuote:
            out.append(quoteOrCallout(quote, depth: depth))
        case let list as ListItemContainer:
            out.append(.list(ordered: list is OrderedList, items: list.listItems.map { item in
                var inner = blocks(of: item, depth: depth + 1)
                if let box = item.checkbox {
                    let mark = Inline.text(box == .checked ? "☑ " : "☐ ")
                    if case .paragraph(let first)? = inner.first {
                        inner[0] = .paragraph(merged([mark] + first))
                    } else {
                        inner.insert(.paragraph([mark]), at: 0)
                    }
                }
                return inner
            }))
        default:
            flatten(node, into: &out)
        }
    }

    /// Below the depth cap, and for blocks of an unknown kind: the leaf blocks of the
    /// subtree in order, in the current block. Walks with a stack, so depth costs no recursion.
    private func flatten(_ node: Markup, into out: inout [Block]) {
        var stack: [Markup] = Array(node.children.reversed())
        while let next = stack.popLast() {
            switch next {
            case is Paragraph, is Heading, is CodeBlock, is HTMLBlock, is Table, is ThematicBreak:
                block(next, depth: maxBlockDepth, into: &out)
            default:
                stack.append(contentsOf: next.children.reversed())
            }
        }
    }

    private func codeBlock(_ block: CodeBlock) -> Block {
        var code = block.code
        if code.hasSuffix("\n") { code.removeLast() }
        let language = block.language?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        if let language, language.lowercased() == "mermaid" { return .diagram(language: "mermaid", code) }
        return .code(language: language, code)
    }

    // MARK: quotes and callouts

    private func quoteOrCallout(_ quote: BlockQuote, depth: Int) -> Block {
        guard let first = quote.child(at: 0) as? Paragraph,
              let callout = calloutHead(first) else {
            return .quote(blocks(of: quote, depth: depth + 1))
        }
        var inner: [Block] = []
        if !callout.rest.isEmpty { inner.append(.paragraph(inlines(of: callout.rest))) }
        for sibling in quote.children.dropFirst() { block(sibling, depth: depth + 1, into: &inner) }
        return .callout(kind: callout.kind, title: callout.title, inner)
    }

    /// `[!kind] Title` on the first line of a paragraph. The rest is what follows the first line break.
    private func calloutHead(_ paragraph: Paragraph) -> (kind: String, title: [Inline], rest: [Markup])? {
        var line: [Markup] = []
        var rest: [Markup] = []
        var broken = false
        for child in paragraph.children {
            if broken { rest.append(child) } else if child is SoftBreak || child is LineBreak { broken = true } else { line.append(child) }
        }
        let leading = line.prefix { $0 is Text }
        let lead = leading.compactMap { ($0 as? Text)?.string }.joined()
        guard lead.hasPrefix("[!") else { return nil }
        let name = lead.dropFirst(2).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        let afterName = lead.dropFirst(2 + name.count)
        guard !name.isEmpty, afterName.hasPrefix("]") else { return nil }
        let remainder = String(afterName.dropFirst().drop { $0 == " " || $0 == "\t" })
        let kind = name.lowercased()
        var title = merged(textInlines(remainder, inLink: false)
            + inlines(of: Array(line.dropFirst(leading.count))))
        title = trimmed(title)
        if title.isEmpty { title = [.text(kind.prefix(1).uppercased() + kind.dropFirst())] }
        return (kind, title, rest)
    }

    // MARK: inlines

    private func inlines(of nodes: some Sequence<Markup>, depth: Int = 0, inLink: Bool = false) -> [Inline] {
        trimmed(convert(nodes, depth: depth, inLink: inLink))
    }

    private func convert(_ nodes: some Sequence<Markup>, depth: Int, inLink: Bool) -> [Inline] {
        var out: [Inline] = []
        var run = ""  // consecutive plain text, scanned for wikilinks once it ends
        func flush() {
            out.append(contentsOf: textInlines(run, inLink: inLink))
            run = ""
        }
        var afterComment = false  // a removed comment must not leave two spaces
        for node in nodes {
            let gapClosed = afterComment
            afterComment = false
            if depth >= maxInlineDepth {
                run += Self.plainText(of: node)
                continue
            }
            switch node {
            case let text as Text:
                run += gapClosed && run.last == " " ? String(text.string.drop { $0 == " " }) : text.string
            case is SoftBreak: run += " "
            case is LineBreak: run += "\n"
            case let html as InlineHTML:
                if follows.takeComment(html.rawHTML) { afterComment = true } else { run += html.rawHTML }
            case let code as InlineCode:
                flush(); out.append(.code(code.code))
            case let emphasis as Emphasis:
                flush(); out.append(.emphasis(convert(emphasis.children, depth: depth + 1, inLink: inLink)))
            case let strong as Strong:
                flush(); out.append(.strong(convert(strong.children, depth: depth + 1, inLink: inLink)))
            case let strike as Strikethrough:
                flush(); out.append(contentsOf: convert(strike.children, depth: depth + 1, inLink: inLink))
            case let image as Image:
                run += Self.plainText(of: image)
            case let link as Link:
                flush()
                let label = convert(link.children, depth: depth + 1, inLink: true)
                if let url = Self.safeURL(link.destination) {
                    out.append(.url(label.isEmpty ? [.text(url.absoluteString)] : label, url))
                } else {
                    out.append(contentsOf: label)
                }
            default:
                run += Self.plainText(of: node)
            }
        }
        flush()
        return merged(out)
    }

    /// Text with wikilinks cut out. Inside the label of an outside link a wikilink is only text.
    private func textInlines(_ text: String, inLink: Bool) -> [Inline] {
        let matches = Wikilink.matches(in: text)
        guard !matches.isEmpty else { return text.isEmpty ? [] : [.text(text)] }
        let bytes = Array(text.utf8)
        func slice(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
        var out: [Inline] = []
        var position = 0
        for match in matches {
            if match.utf8Range.lowerBound > position { out.append(.text(slice(position..<match.utf8Range.lowerBound))) }
            position = match.utf8Range.upperBound
            out.append(.link([], .missing, raw: String(links.count)))  // resolved by the caller
            links.append(PendingLink(link: match.link, plain: inLink))
        }
        if position < bytes.count { out.append(.text(slice(position..<bytes.count))) }
        return merged(out)
    }

    /// Whitespace at the edges of a line of inlines is no content.
    private func trimmed(_ inlines: [Inline]) -> [Inline] {
        var out = inlines
        if case .text(let first)? = out.first {
            let value = String(first.drop { $0 == " " || $0 == "\t" })
            if value.isEmpty { out.removeFirst() } else { out[0] = .text(value) }
        }
        if case .text(let last)? = out.last {
            var value = last
            while value.last == " " || value.last == "\t" { value.removeLast() }
            if value.isEmpty { out.removeLast() } else { out[out.count - 1] = .text(value) }
        }
        return out
    }

    // MARK: helpers

    /// The scheme allow-list. Control characters and spaces are dropped before the check, as
    /// browsers do, so `java\tscript:` is no way round it.
    private static func safeURL(_ destination: String?) -> URL? {
        guard let destination else { return nil }
        let cleaned = String(destination.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }.map(Character.init))
        let scheme = cleaned.prefix { $0 != ":" }.lowercased()
        guard cleaned.contains(":"), ["http", "https", "mailto"].contains(scheme),
              let url = URL(string: cleaned), let real = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(real) else { return nil }
        return url
    }

    /// All text under a node, without marks, found with a stack.
    private static func plainText(of node: Markup) -> String {
        var text = ""
        var stack: [Markup] = [node]
        while let next = stack.popLast() {
            switch next {
            case let t as Text: text += t.string
            case let c as InlineCode: text += c.code
            case let h as InlineHTML: text += h.rawHTML
            case is SoftBreak: text += " "
            case is LineBreak: text += "\n"
            default: stack.append(contentsOf: next.children.reversed())
            }
        }
        return text
    }
}
