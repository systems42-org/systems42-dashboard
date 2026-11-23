import Foundation
import Systems42Kit

/// What a diagram shows. Mermaid text, or a graph of the Kit with the name of its layout.
public enum DiagramSource: Equatable, Sendable {
    case mermaid(String)
    case graph(Graph, layout: String)
}

/// The layouts of a graph. The page knows how to style and lay out each one.
public enum DiagramLayout {
    public static let termNetwork = "term-network"
    public static let metamodel = "metamodel"
}

/// Limits on what the web view is asked to draw. A larger diagram shows a message and the text list instead.
public enum DiagramLimits {
    /// The most bytes of Mermaid text. Mermaid's own `maxTextSize` is set to the same number, so the two cannot disagree.
    public static let mostMermaidBytes = 50_000
    /// The most nodes and edges of a graph.
    public static let mostGraphNodes = 1_500
    public static let mostGraphEdges = 4_000
    /// How long one draw may take. A diagram that needs longer shows a message, and its web view is dropped.
    public static let renderTimeout = Duration.seconds(10)
    /// The most web views that live at once in one window. The others show a placeholder with the text list.
    public static let mostLiveViews = 4
    /// The most Mermaid blocks of one page body that are drawn. Further blocks show their source.
    public static let mostBlocksPerPage = 20
}

/// A source checked and prepared for the page: the Mermaid text without its click lines, and the nodes
/// that open a page. Only these nodes report a click.
struct DiagramContent: Equatable, Sendable {
    struct Node: Equatable, Sendable {
        let id: String
        /// The page the node opens. Nil for a node that is no page: a content type of the metamodel graph.
        let ref: PageRef?
    }

    let source: DiagramSource
    /// The Mermaid text with every `click` line taken out. Nothing in it can address a URL or a callback.
    let mermaidText: String
    /// The nodes that open a page, in the order of the diagram, each id once.
    let nodes: [Node]
    let tooLarge: Bool

    var nodeIDs: Set<String> { Set(nodes.map(\.id)) }

    func node(id: String) -> Node? { nodes.first { $0.id == id } }

    /// Whether Mermaid text has more than one thing to draw. A leaf requirement's breakdown is one box: not worth a diagram.
    var drawsSomething: Bool {
        guard case .mermaid = source else { return true }
        if mermaidText.hasPrefix("sequenceDiagram") { return true }
        let ignored = ["click ", "style ", "classDef ", "linkStyle ", "class "]
        let lines = mermaidText.split(separator: "\n").dropFirst().map { $0.drop { $0 == " " } }
        return lines.filter { line in !line.isEmpty && !ignored.contains { line.hasPrefix($0) } }.count > 1
    }

    /// `allowsLinks` is false for a diagram that wiki text wrote itself (a Mermaid block of a page): no node of it opens a page.
    init(_ source: DiagramSource, allowsLinks: Bool = true) {
        self.source = source
        switch source {
        case .mermaid(let text):
            let split = Self.split(text)
            mermaidText = split.text
            nodes = allowsLinks ? split.nodes : []
            tooLarge = text.utf8.count > DiagramLimits.mostMermaidBytes
        case .graph(let graph, let layout):
            mermaidText = ""
            nodes = allowsLinks ? (layout == DiagramLayout.metamodel ? Self.types(of: graph) : Self.nodes(of: graph)) : []
            tooLarge = graph.nodes.count > DiagramLimits.mostGraphNodes || graph.edges.count > DiagramLimits.mostGraphEdges
        }
    }

    /// Takes the click statements out of Mermaid text. The Kit writes `click <id> "systems42://page?folder=..&stem=.."`
    /// on a line of its own: that line gives a node. A click statement anywhere else, also after a `;`, is
    /// cut and gives nothing. The scan is linear and uses no pattern matching.
    private static func split(_ text: String) -> (text: String, nodes: [Node]) {
        var kept: [String] = []
        var nodes: [Node] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if isClick(trimmed) {
                if let node = node(of: trimmed), seen.insert(node.id).inserted { nodes.append(node) }
                continue
            }
            var cut = false
            var statements: [Substring] = []
            for statement in line.split(separator: ";", omittingEmptySubsequences: false) {
                if isClick(statement.drop { $0 == " " || $0 == "\t" }) { cut = true } else { statements.append(statement) }
            }
            kept.append(cut ? statements.joined(separator: ";") : String(line))
        }
        return (kept.joined(separator: "\n"), nodes)
    }

    private static func isClick(_ statement: Substring) -> Bool {
        statement.lowercased().hasPrefix("click ")
    }

    /// The node of a line `click <id> "<url>"`, when the url is a page reference of the app.
    private static func node(of line: Substring) -> Node? {
        let rest = line.dropFirst(6)
        guard let space = rest.firstIndex(of: " "), let open = rest.firstIndex(of: "\""),
              let close = rest.lastIndex(of: "\""), open < close else { return nil }
        let id = String(rest[..<space])
        let target = String(rest[rest.index(after: open)..<close])
        guard !id.isEmpty, let url = URL(string: target), case .page(let ref)? = LinkAction(url: url) else { return nil }
        return Node(id: id, ref: ref)
    }

    /// The content types of the metamodel graph. A type node carries a `prefix`, a section group does not.
    private static func types(of graph: Graph) -> [Node] {
        var seen = Set<String>()
        return graph.nodes.compactMap { node in
            guard node.data["prefix"]?.string != nil, !node.id.isEmpty, seen.insert(node.id).inserted else { return nil }
            return Node(id: node.id, ref: nil)
        }
    }

    /// The nodes whose `url` is `/page/<folder>/<stem>`, as the term network writes it.
    private static func nodes(of graph: Graph) -> [Node] {
        var nodes: [Node] = []
        var seen = Set<String>()
        for node in graph.nodes {
            let parts = (node.data["url"]?.string ?? "").split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0].isEmpty, parts[1] == "page", !parts[2].isEmpty, !parts[3].isEmpty,
                  !node.id.isEmpty, seen.insert(node.id).inserted else { continue }
            nodes.append(Node(id: node.id, ref: PageRef(folder: String(parts[2]), stem: String(parts[3]))))
        }
        return nodes
    }
}
