import Foundation

/// How a click in a diagram addresses a page.
public enum LinkStyle: Sendable {
    /// The routes of the Go dashboard, `/functional-requirements/<stem>`, `/goals#<id>`, `/page/<folder>/<stem>`.
    /// The golden data holds them.
    case dashboard
    /// The page reference of the app: `systems42://page?folder=<folder>&stem=<stem>`. This is the form
    /// `LinkAction` in Systems42UI reads. The Kit builds it itself and imports no UI code.
    case page
}

/// Node ids of one diagram. The id of the Go dashboard (`DiagramNodeID`) stays where it is unique and
/// safe. A second page that would get the same id, and a page whose id is a Mermaid keyword, get a
/// suffix `_2`, `_3` and so on. Ids that the builder writes itself (`CORE`, `V`) are given as `reserved`.
struct NodeIDs {
    /// Words that end or start a Mermaid statement. Compared in lower case.
    static let keywords: Set<String> = [
        "end", "click", "style", "class", "classdef", "subgraph", "graph", "flowchart", "direction",
        "linkstyle", "default", "call", "href", "interpolate", "accdescr", "acctitle", "participant", "actor",
        "note", "loop", "alt", "opt", "par", "rect", "activate", "deactivate", "title", "autonumber",
    ]

    private var taken: Set<String>
    private var byKey: [String: String] = [:]

    init(reserved: [String] = []) {
        taken = Set(reserved)
    }

    /// The id of the thing with this key. Asking again for the same key gives the same id.
    mutating func id(_ key: String, base: String) -> String {
        if let known = byKey[key] { return known }
        var candidate = base
        var n = 2
        while taken.contains(candidate) || Self.keywords.contains(candidate.lowercased()) {
            candidate = "\(base)_\(n)"
            n += 1
        }
        taken.insert(candidate)
        byKey[key] = candidate
        return candidate
    }

    /// The id for a page, from the Go rule on its id.
    mutating func id(of page: Page) -> String {
        id(Self.key(of: page), base: Common.diagramNodeID(page.id))
    }

    static func key(of page: Page) -> String {
        "page:" + page.ref.folder + "/" + page.ref.stem
    }
}

extension ProjectionModel {
    /// Characters that stay as they are in a click target.
    private static func isPlain(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x41 && scalar.value <= 0x5A)
            || (scalar.value >= 0x61 && scalar.value <= 0x7A) || scalar == "." || scalar == "_" || scalar == "-"
    }

    /// A stem, folder or id for a click target: `A-Za-z0-9._-` stay, every other byte is percent-encoded.
    static func encode(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            if isPlain(scalar) { out.unicodeScalars.append(scalar); continue }
            for byte in String(scalar).utf8 { out += String(format: "%%%02X", byte) }
        }
        return out
    }

    private static let pageRoute = "/page/"
    private static let appScheme = "systems42://page?folder="
    private static let appStem = "&stem="

    /// The target of the click on a page. In the `dashboard` style a goal is addressed by its id
    /// in the goal list, a requirement by its own route and every other page by `/page/<folder>/<stem>`.
    func link(to page: Page, style: LinkStyle) -> String {
        switch style {
        case .page:
            return Self.appScheme + Self.encode(page.ref.folder) + Self.appStem + Self.encode(page.ref.stem)
        case .dashboard:
            let folder = page.ref.folder
            if folder == self.folder(ofType: FR.goalType) { return "/" + Self.encode(folder) + "#" + Self.encode(page.id) }
            if folder == self.folder(ofType: FR.requirementType) { return "/" + Self.encode(folder) + "/" + Self.encode(page.stem) }
            return Self.pageRoute + Self.encode(folder) + "/" + Self.encode(page.stem)
        }
    }
}

/// The types and fields a projection reads, by the name of its projection page. The constants of a
/// projection file are its source. A test compares them with the `reads:` of the page in the metamodel.
struct ProjectionDeclaration: Sendable {
    struct Read: Sendable {
        let type: String
        let fields: [String]
    }

    let name: String
    let reads: [Read]

    init(_ name: String, _ reads: [(String, [String])]) {
        self.name = name
        self.reads = reads.map { Read(type: $0.0, fields: $0.1) }
    }
}
