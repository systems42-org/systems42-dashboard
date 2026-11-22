import Foundation
import Markdown

/// Turns the Markdown body of a page into blocks. Reads no file and opens no URL.
///
/// `resolve` tells what a wikilink points at, `title` what to show for a link without a label.
/// Page text never becomes anything but these values: raw HTML is text, and a link
/// is an outside link only with the scheme `http`, `https` or `mailto`.
public func renderPage(
    _ body: String,
    resolve: (Wikilink) -> LinkTarget,
    title: (LinkTarget) -> String?
) -> RenderedPage {
    withoutActuallyEscaping(resolve) { resolve in
        withoutActuallyEscaping(title) { title in
            let renderer = PageRenderer(resolve: resolve, title: title)
            let text = renderer.prepare(body.replacingOccurrences(of: "\r\n", with: "\n"))
            let blocks = renderer.blocks(of: Document(parsing: text), depth: 0)
            return RenderedPage(follows: renderer.follows, blocks: blocks)
        }
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
    switch page.blocks.first {
    case .paragraph(let inlines)?, .heading(_, let inlines)?:
        if page.blocks.count == 1 { return inlines }
    default:
        break
    }
    return [.text(text)]
}

private let maxBlockDepth = 10
private let maxInlineDepth = 32

private final class PageRenderer {
    let resolve: (Wikilink) -> LinkTarget
    let title: (LinkTarget) -> String?
    private(set) var follows: [String] = []
    private var seenFollows: Set<String> = []

    init(resolve: @escaping (Wikilink) -> LinkTarget, title: @escaping (LinkTarget) -> String?) {
        self.resolve = resolve
        self.title = title
    }

    // MARK: follows

    private func addFollow(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, seenFollows.insert(trimmed.lowercased()).inserted { follows.append(trimmed) }
    }

    /// Before parsing, line by line outside fenced code:
    /// - removes `> follows ...` notes (FR-035). Same rule as the Go dashboard: a note without a
    ///   link and with more than 6 words or any of `.!?;:` is an ordinary quote.
    /// - bounds how deep the text can nest. The parser overflows a 512 KB stack at about 400 levels
    ///   of quotes, lists or emphasis, so a hostile page must not reach that.
    func prepare(_ body: String) -> String {
        var kept: [String] = []
        var fence: (char: Character, length: Int)?
        var emphasis = 0  // delimiters used so far in this paragraph
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if let open = Self.fence(of: line) {
                if let current = fence {
                    if open.char == current.char, open.length >= current.length { fence = nil }
                } else {
                    fence = open
                }
                emphasis = 0
                kept.append(String(line))
            } else if fence != nil {
                kept.append(String(line))
            } else if let note = Self.followsNote(line), takeFollowsNote(note) {
                continue
            } else {
                if line.allSatisfy(\.isWhitespace) { emphasis = 0 }
                kept.append(Self.boundedEmphasis(Self.boundedPrefix(line), used: &emphasis))
            }
        }
        return kept.joined(separator: "\n")
    }

    /// Adds the formats of a follows note. False for text that is an ordinary quote.
    private func takeFollowsNote(_ note: String) -> Bool {
        let links = Wikilink.all(in: note)
        if links.isEmpty {
            if note.split(whereSeparator: \.isWhitespace).count > 6 || note.contains(where: { ".!?;:".contains($0) }) {
                return false
            }
            addFollow(note.lowercased().hasPrefix("the ") ? String(note.dropFirst(4)) : note)
        } else {
            links.forEach { addFollow($0.name) }
        }
        return true
    }

    private static let maxMarkers = 12, maxIndent = 48, maxDelimiters = 150

    /// Keeps the first quote and list markers of a line, and at most 48 spaces of indent.
    /// Further markers are dropped and their text stays.
    private static func boundedPrefix(_ line: Substring) -> Substring {
        var out = ""
        var rest = line
        var markers = 0
        var indent = 0
        while let first = rest.first {
            if first == " " || first == "\t" {
                if markers == 0 { indent += 1 }
                if markers == 0 ? indent <= maxIndent : markers <= maxMarkers { out.append(first) }
                rest = rest.dropFirst()
                continue
            }
            let width = markerWidth(rest)
            guard width > 0 else { break }
            markers += 1
            if markers <= maxMarkers { out += rest.prefix(width) }
            rest = rest.dropFirst(width)
        }
        return markers <= maxMarkers && indent <= maxIndent ? line : Substring(out + rest.drop { $0 == " " || $0 == "\t" })
    }

    /// The length of a quote or list marker at the start of `text`, else 0.
    private static func markerWidth(_ text: Substring) -> Int {
        guard let first = text.first else { return 0 }
        if first == ">" { return 1 }
        let next = text.dropFirst().first
        if "-*+".contains(first), next == " " || next == "\t" { return 1 }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        if (1...9).contains(digits.count), let mark = text.dropFirst(digits.count).first, mark == "." || mark == ")",
           let after = text.dropFirst(digits.count + 1).first, after == " " || after == "\t" {
            return digits.count + 1
        }
        return 0
    }

    /// Escapes `*` and `_` beyond the 150th of a paragraph, outside code spans, so that
    /// emphasis cannot nest deeper than that. The escaped character shows as itself.
    private static func boundedEmphasis(_ line: Substring, used: inout Int) -> String {
        guard line.contains(where: { $0 == "*" || $0 == "_" }) else { return String(line) }
        var out = ""
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                out.append(c)
                if i + 1 < chars.count { out.append(chars[i + 1]) }
                i += 2
            } else if c == "`" {
                let run = chars[i...].prefix { $0 == "`" }.count
                var end = i + run
                var close: Int?
                while end < chars.count {
                    if chars[end] == "`" {
                        let length = chars[end...].prefix { $0 == "`" }.count
                        if length == run { close = end + length; break }
                        end += length
                    } else {
                        end += 1
                    }
                }
                let stop = close ?? i + run
                out += String(chars[i..<stop])
                i = stop
            } else {
                if c == "*" || c == "_" {
                    used += 1
                    if used > maxDelimiters { out.append("\\") }
                }
                out.append(c)
                i += 1
            }
        }
        return out
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

    /// `<!-- follows [[Q42]], https://... -->`: the links are formats the page follows.
    private func takeFollowsComment(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"), trimmed.count >= 7 else { return false }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.hasPrefix("follows"), inner.dropFirst(7).first.map(\.isWhitespace) ?? true else { return false }
        Wikilink.all(in: inner).forEach { addFollow($0.name) }
        return true
    }

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
            if !takeFollowsComment(html.rawHTML) {
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
        for node in nodes {
            if depth >= maxInlineDepth {
                run += Self.plainText(of: node)
                continue
            }
            switch node {
            case let text as Text: run += text.string
            case is SoftBreak: run += " "
            case is LineBreak: run += "\n"
            case let html as InlineHTML:
                if !takeFollowsComment(html.rawHTML) { run += html.rawHTML }
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
            let target = resolve(match.link)
            let shown = match.link.label ?? title(target) ?? match.link.name
            out.append(inLink ? .text(shown) : .link([.text(shown)], target, raw: match.link.target))
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
