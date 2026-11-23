import Foundation
import WebKit
import Systems42Kit

/// The one channel between the app and the page. Data goes in as JSON arguments of
/// `callAsyncJavaScript`, so no wiki text is ever spliced into script. A click comes back as a string.
enum DiagramBridge {
    /// The name of the message handler the page posts clicks to.
    static let handlerName = "select"

    /// What the page gets: the whole diagram as data.
    struct Payload: Encodable {
        let kind: String
        let theme: String
        let text: String
        let graph: Graph?
        let preset: String
        let links: [String]
        /// Mermaid's `maxTextSize`: the app's own limit.
        let maxText: Int
        /// The frame colour of a node type, by id prefix, as `#rrggbb` for this theme.
        let frameColours: [String: String]
    }

    static func payload(for content: DiagramContent, dark: Bool, frameColours: [String: [String]] = [:]) -> Payload {
        let theme = dark ? "dark" : "light"
        let links = content.nodes.map(\.id)
        var colours: [String: String] = [:]
        for (prefix, pair) in frameColours where pair.count == 2 { colours[prefix] = dark ? pair[1] : pair[0] }
        switch content.source {
        case .mermaid:
            return Payload(kind: "mermaid", theme: theme, text: content.mermaidText, graph: nil, preset: "", links: links,
                           maxText: DiagramLimits.mostMermaidBytes, frameColours: colours)
        case .graph(let graph, let layout):
            return Payload(kind: "graph", theme: theme, text: "", graph: graph, preset: layout, links: links,
                           maxText: DiagramLimits.mostMermaidBytes, frameColours: colours)
        }
    }

    /// The payload as the property-list value `callAsyncJavaScript` takes. Built with the encoders of Foundation.
    static func argument(for payload: Payload) throws -> Any {
        let data = try JSONEncoder().encode(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// The id in a message of the page, or nil. Only a string that is the id of a node of the diagram
    /// on show is accepted. A page cannot name any other page.
    static func validated(_ body: Any, known: Set<String>) -> String? {
        guard let id = body as? String, known.contains(id) else { return nil }
        return id
    }

    // MARK: Content rule list

    /// Rules that block every request, then lift the block for the files of the bundled folder.
    /// The page is loaded from `file:`, so the lifted pattern names that folder and nothing else.
    static func ruleListJSON(allowing folder: URL) throws -> String {
        let prefix = folder.absoluteString.hasSuffix("/") ? folder.absoluteString : folder.absoluteString + "/"
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^" + escaped(prefix)], "action": ["type": "ignore-previous-rules"]],
        ]
        let data = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Escapes what the pattern language of content rules takes as special.
    static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            if ".^$*+?()[]{}|\\".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// Whether the URL is the bundled page itself. The web view allows that navigation once, for the first load.
    static func allowsNavigation(to url: URL?, page: URL) -> Bool {
        guard let url else { return false }
        return url.standardizedFileURL == page.standardizedFileURL
    }
}
