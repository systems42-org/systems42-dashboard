import Foundation
import Observation
import Systems42Kit

/// What the Metamodel window shows: the constructs of the open wiki's `_system/metamodel/` and
/// `_system/anchors/`, as entries. Every text comes from there (CON-006). The model reads
/// through the session, so a reloaded wiki shows new texts on the next read.
@MainActor @Observable public final class MetamodelModel {
    public struct Fact: Equatable, Sendable {
        public let label, value: String
    }

    /// A pointer to another entry.
    public struct Link: Equatable, Sendable {
        public let kind, name, title: String
    }

    public struct LinkGroup: Equatable, Sendable {
        public let title: String
        public let links: [Link]
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public let kind, name, title, definition, body: String
        public var id: String { kind + "/" + name }
        public var facts: [Fact] = []
        public var fields: [MMField] = []
        public var groups: [LinkGroup] = []
        /// The first web address of an anchor.
        public var reference: URL?
        /// A live page of the wiki, for a type.
        public var example: Page?
        /// What the entry says about its example, for a type. Empty for other kinds.
        public var exampleText = ""

        /// Compares everything the entry shows. The example is shown through `exampleText`.
        public static func == (a: Entry, b: Entry) -> Bool {
            a.id == b.id && a.title == b.title && a.definition == b.definition && a.body == b.body
                && a.facts == b.facts && a.fields == b.fields && a.groups == b.groups
                && a.reference == b.reference && a.exampleText == b.exampleText && a.example?.ref == b.example?.ref
        }
    }

    /// The types and relations of a graph in a readable form: types grouped by section, relations as lines.
    public struct GraphOutline: Equatable, Sendable {
        public struct Group: Equatable, Sendable {
            public let title: String
            public let lines: [String]
        }
        public var groups: [Group] = []
        public var relations: [String] = []
        public var universal: [String] = []
    }

    public enum Mode: Sendable { case entries, graph }

    // The kinds of construct are fixed by the metamodel format, their names are the window's labels.
    public static let types = "Types", relations = "Relations", frameworks = "Frameworks", projections = "Projections"
    public static let rules = "Rules", anchors = "Anchors", notations = "Notations"
    public static let noExample = "No page of this type in this wiki yet."

    public let kinds: [String] = [types, relations, frameworks, projections, rules, anchors, notations]

    public private(set) var selectedKind = MetamodelModel.types
    public private(set) var showsVersionNotice = false
    /// Says that a click found no entry, nil otherwise.
    public private(set) var noEntryText: String?
    public var mode = Mode.entries
    /// The graph mode's data: framework blocks as groups, types as nodes, relations as edges. Nil until loaded.
    public private(set) var drawnGraph: Graph?
    @ObservationIgnored private var graphRevision: Int?

    private var chosenEntryID: String?
    private var chosenSection: WikiSection.ID?
    /// Weak: the session owns this model, so a strong reference would be a cycle. A gone session gives empty results.
    private weak var session: WikiSession?

    private struct Built {
        var byKind: [String: [Entry]] = [:]
        var byID: [String: Entry] = [:]
    }

    /// The entries of the loaded wiki, built once per revision of the session.
    @ObservationIgnored private var cache: (revision: Int, built: Built)?

    public init(session: WikiSession) {
        self.session = session
        chosenEntryID = entries(of: Self.types).first?.id
    }

    private var built: Built {
        guard let session else { return Built() }
        let revision = session.revision
        if let cache, cache.revision == revision { return cache.built }
        let metamodel = session.metamodel
        var built = Built()
        for kind in kinds {
            var list: [Entry] = []
            // A name that repeats inside one kind keeps its first entry.
            for entry in makeEntries(of: kind, in: metamodel) where built.byID[entry.id] == nil {
                built.byID[entry.id] = entry
                list.append(entry)
            }
            built.byKind[kind] = list
        }
        cache = (revision, built)
        return built
    }

    /// The revision of the loaded wiki. It changes when the wiki is replaced.
    public var revision: Int { session?.revision ?? 0 }

    /// Computes the graph of the loaded metamodel off the main thread, once per revision. A result of an older revision is dropped.
    public func loadGraph() async {
        guard let session else { return }
        let revision = session.revision
        guard graphRevision != revision else { return }
        let store = session.store, metamodel = session.metamodel
        let graph = await Task.detached(priority: .userInitiated) {
            Projections(store: store, metamodel: metamodel, agreedOnly: false).graph("metamodel-graph")
        }.value
        guard !Task.isCancelled, self.session?.revision == revision else { return }
        drawnGraph = graph
        graphRevision = revision
    }

    // MARK: Entries

    public func entries(of kind: String) -> [Entry] {
        built.byKind[kind] ?? []
    }

    private func makeEntries(of kind: String, in m: Metamodel) -> [Entry] {
        switch kind {
        case Self.types: return m.types.map { typeEntry($0, in: m) }
        case Self.relations: return m.relations.map(constructEntry)
        case Self.frameworks: return m.frameworks.map(frameworkEntry)
        case Self.projections: return m.projections.map(constructEntry)
        case Self.rules: return m.rules.map(constructEntry)
        case Self.anchors: return m.anchors.map { anchorEntry($0, in: m) }
        case Self.notations: return m.notations.map(constructEntry)
        default: return []
        }
    }

    /// The entry a wikilink target leads to. Only anchors and metamodel pages have one.
    public func entry(for target: LinkTarget) -> Entry? {
        guard let m = session?.metamodel else { return nil }
        switch target {
        case .anchor(let name):
            return m.anchor(name).flatMap { built.byID[Self.id(Self.anchors, $0.name)] }
        case .metamodel(let name):
            let key = name.lowercased()
            func named(_ c: MMConstruct) -> Bool {
                c.name.lowercased() == key || aliases(of: c).contains { $0.lowercased() == key }
            }
            if let type = m.type(named: name) ?? m.types.first(where: { $0.name.lowercased() == key }) {
                return built.byID[Self.id(Self.types, type.name)]
            }
            for list in [m.relations, m.projections, m.rules, m.notations] {
                if let found = list.first(where: named) { return built.byID[Self.id(kind(of: found), found.name)] }
            }
            return m.frameworks.first { $0.name.lowercased() == key }.flatMap { built.byID[Self.id(Self.frameworks, $0.name)] }
        case .page, .source, .missing:
            return nil
        }
    }

    /// The type entries of a section, in the order its block lists them.
    public func entries(forSection id: WikiSection.ID) -> [Entry] {
        guard let m = session?.metamodel else { return [] }
        guard let section = m.sections.first(where: { $0.id == id }) else { return [] }
        var seen = Set<String>()
        return section.types.compactMap { m.type(named: $0) }.filter { seen.insert($0.name).inserted }
            .compactMap { built.byID[Self.id(Self.types, $0.name)] }
    }

    private static func id(_ kind: String, _ name: String) -> String { kind + "/" + name }

    private func kind(of construct: MMConstruct) -> String {
        switch construct.construct {
        case "relation": Self.relations
        case "projection": Self.projections
        case "rule": Self.rules
        default: Self.notations
        }
    }

    /// The first page of the type in the open wiki. Nil when it has none.
    public func example(forType name: String) -> Page? {
        guard let session, let type = session.metamodel.type(named: name), let folder = type.folder.split(separator: "/").last else { return nil }
        return session.store.pages(in: String(folder)).first
    }

    /// The explanation of a field in its type page. Nil when the type or field is unknown or has no doc.
    public func fieldHelp(type: String, field: String) -> String? {
        mmField(type: type, field: field)?.doc
    }

    /// The values the field allows. Empty for a field without a fixed set.
    public func fieldValues(type: String, field: String) -> [String] {
        mmField(type: type, field: field)?.values ?? []
    }

    private func mmField(type: String, field: String) -> MMField? {
        session?.metamodel.type(named: type)?.fields.first { $0.name == field }
    }

    // MARK: Version notice

    /// A line for under the toolbar and the text it opens. Nil when the wiki's metamodel is supported.
    public var versionNotice: (line: String, explanation: String)? {
        session.flatMap { Self.notice(for: $0.metamodel.version) }
    }

    static func notice(for state: VersionState) -> (line: String, explanation: String)? {
        let anyway = "The app shows the wiki anyway, but names, fields and diagrams may be wrong or missing."
        switch state {
        case .supported:
            return nil
        case .unsupported(let found, let supported):
            let list = supported.joined(separator: ", ")
            return (
                "This wiki's metamodel is version \(found). This app supports \(list).",
                "This wiki's metamodel is version \(found). This app supports version \(list). \(anyway) "
                    + "Update the app to one that supports \(found), or bring the metamodel of the wiki to a supported version."
            )
        case .missing(let supported):
            let list = supported.joined(separator: ", ")
            return (
                "This wiki's metamodel names no version. This app supports \(list).",
                "This wiki's metamodel names no version. This app supports version \(list). \(anyway) "
                    + "Add the version to the metamodel's own page, or update the app."
            )
        }
    }

    // MARK: Selection

    /// The entry that is chosen, nil when the wiki no longer has it.
    public var selectedEntryID: String? {
        chosenEntryID.flatMap { built.byID[$0] == nil ? nil : $0 }
    }

    /// Set while the list is limited to the types of one section. A section that vanished from the wiki sets nothing.
    public var sectionFilter: WikiSection.ID? {
        chosenSection.flatMap { entries(forSection: $0).isEmpty ? nil : $0 }
    }

    /// The entries the list shows: all of the kind, or the types of the filtered section.
    public var shownEntries: [Entry] {
        if let sectionFilter, selectedKind == Self.types { return entries(forSection: sectionFilter) }
        return entries(of: selectedKind)
    }

    public var selectedEntry: Entry? {
        selectedEntryID.flatMap { built.byID[$0] }
    }

    private func clearNotices() {
        showsVersionNotice = false
        noEntryText = nil
    }

    public func select(kind: String) {
        guard kinds.contains(kind) else { return }
        selectedKind = kind
        chosenSection = nil
        clearNotices()
        mode = .entries
        chosenEntryID = entries(of: kind).first?.id
    }

    public func select(entry id: String?) {
        chosenEntryID = id
        clearNotices()
    }

    /// Opens the entry a target leads to. A target with no entry changes nothing.
    @discardableResult
    public func show(_ target: LinkTarget) -> Bool {
        guard let found = entry(for: target) else { return false }
        show(entry: found)
        return true
    }

    /// Opens the entry a link of another entry points at.
    public func show(link: Link) {
        if let found = built.byID[Self.id(link.kind, link.name)] { show(entry: found) }
    }

    public func show(entry found: Entry) {
        selectedKind = found.kind
        chosenSection = nil
        clearNotices()
        mode = .entries
        chosenEntryID = found.id
    }

    /// Opens the type entries of a section.
    @discardableResult
    public func show(section id: WikiSection.ID) -> Bool {
        let found = entries(forSection: id)
        guard let first = found.first else { return false }
        selectedKind = Self.types
        chosenSection = id
        clearNotices()
        mode = .entries
        chosenEntryID = first.id
        return true
    }

    /// Says in the window that the name has no entry.
    public func showNoEntry(for target: LinkTarget) {
        let name: String
        switch target {
        case .anchor(let value), .metamodel(let value), .source(let value): name = value
        case .page(let ref): name = ref.stem
        case .missing: name = ""
        }
        noEntryText = "The metamodel of this wiki has no entry for \"\(name)\"."
        showsVersionNotice = false
    }

    /// Says in the window that the section has no type to explain.
    public func showNoEntry(forSection id: WikiSection.ID) {
        let title = session?.metamodel.sections.first { $0.id == id }?.title ?? id
        noEntryText = "The metamodel of this wiki names no type for the section \"\(title)\"."
        showsVersionNotice = false
    }

    /// Lists all entries of the kind again.
    public func showAll() {
        chosenSection = nil
    }

    public func showVersionNotice() {
        guard versionNotice != nil else {
            noEntryText = "The metamodel version of this wiki is supported, so there is nothing to explain."
            return
        }
        noEntryText = nil
        showsVersionNotice = true
    }

    // MARK: Graph

    /// The metamodel graph of the Graph mode. A web view draws it later (issue 128).
    public var graph: Graph {
        guard let session else { return Graph() }
        return Projections(store: session.store, metamodel: session.metamodel, agreedOnly: false).graph("metamodel-graph") ?? Graph()
    }

    public var graphOutline: GraphOutline {
        let g = graph
        var outline = GraphOutline()
        var labels: [String: String] = [:]
        for node in g.nodes where node.data["is_block"]?.bool != true {
            labels[node.id] = node.data["label"]?.string ?? node.id
        }
        func line(_ node: Graph.Node) -> String {
            let prefix = node.data["prefix"]?.string ?? ""
            return prefix.isEmpty ? (labels[node.id] ?? node.id) : "\(labels[node.id] ?? node.id) (\(prefix))"
        }
        for block in g.nodes where block.data["is_block"]?.bool == true {
            let lines = g.nodes.filter { $0.data["parent"]?.string == block.id }.map(line)
            outline.groups.append(GraphOutline.Group(title: block.data["label"]?.string ?? block.id, lines: lines))
        }
        let loose = g.nodes.filter { $0.data["is_block"]?.bool != true && $0.data["parent"] == nil }
        if !loose.isEmpty { outline.groups.append(GraphOutline.Group(title: "No section", lines: loose.map(line))) }
        outline.relations = g.edges.map { edge in
            let label = edge.data["label"]?.string ?? ""
            let cardinality = edge.data["cardinality"]?.string ?? ""
            return "\(edge.source) → \(edge.target): \(label)" + (cardinality.isEmpty ? "" : " (\(cardinality))")
        }
        if case .list(let items)? = g.extra["universal"] {
            outline.universal = items.compactMap { item in
                guard case .map(let map) = item else { return nil }
                return "\(map["from"]?.string ?? "") → \(map["to"]?.string ?? ""): \(map["field"]?.string ?? "")"
            }
        }
        return outline
    }

    // MARK: Building entries

    /// Keys of a relation page. They are the format of the metamodel, as in the metamodel graph. Open debt (CON-006).
    private static let edgesKey = "edges", fromKey = "from", toKey = "to", anyType = "any"
    private static let aliasesKey = "aliases"
    private static let hiddenKeys: Set<String> = ["type", "construct", "name", "aliases", "summary", "edges"]

    private func aliases(of construct: MMConstruct) -> [String] {
        switch construct.frontmatter[Self.aliasesKey] {
        case .list(let items)?: items
        case .text(let item)?: [item]
        default: []
        }
    }

    private func typeEntry(_ type: MMType, in m: Metamodel) -> Entry {
        var entry = Entry(kind: Self.types, name: type.name, title: type.label.isEmpty ? type.name : type.label,
                          definition: type.definition, body: MetaBody.withoutHeading(type.body))
        func fact(_ label: String, _ value: String) { if !value.isEmpty { entry.facts.append(Fact(label: label, value: value)) } }
        fact("Name", type.name)
        fact("Prefix", type.prefix)
        fact("Folder", type.folder)
        fact("Section", m.sections.first { $0.id == type.block }.map { "\($0.id) · \($0.title)" } ?? type.block)
        fact("Lifecycle", type.lifecycle.isEmpty ? "" : ([type.lifecycle] + (m.lifecycles[type.lifecycle].map { [$0.joined(separator: ", ")] } ?? [])).joined(separator: ": "))
        fact("Stereotypes", type.stereotypes.joined(separator: ", "))
        entry.fields = type.fields

        var relationLinks: [Link] = []
        var seen = Set<String>()
        for relation in m.relations {
            let touches = (relation.entries[Self.edgesKey] ?? []).contains { edge in
                [edge[Self.fromKey] ?? "", edge[Self.toKey] ?? ""].contains { $0 == type.name || $0 == Self.anyType }
            }
            if touches, seen.insert(relation.name).inserted {
                relationLinks.append(Link(kind: Self.relations, name: relation.name, title: relation.name))
            }
        }
        let anchorLinks = type.anchors.map { name -> Link in
            let found = m.anchor(name)
            return Link(kind: Self.anchors, name: found?.name ?? name, title: found?.title ?? name)
        }
        let projectionLinks = type.projections.map { Link(kind: Self.projections, name: $0, title: $0) }
        for (title, links) in [("Relations", relationLinks), ("Anchors", anchorLinks), ("Projections", projectionLinks)] where !links.isEmpty {
            entry.groups.append(LinkGroup(title: title, links: links))
        }
        let example = example(forType: type.name)
        entry.example = example
        entry.exampleText = example.map { "\($0.id) \($0.title)" } ?? Self.noExample
        return entry
    }

    private func constructEntry(_ construct: MMConstruct) -> Entry {
        var entry = Entry(kind: kind(of: construct), name: construct.name, title: construct.name, definition: construct.definition,
                          body: MetaBody.withoutHeading(construct.body))
        for key in construct.frontmatter.keys.sorted() where !Self.hiddenKeys.contains(key) {
            switch construct.frontmatter[key] {
            case .text(let value)?: if !value.isEmpty { entry.facts.append(Fact(label: key, value: value)) }
            case .list(let items)?: if !items.isEmpty { entry.facts.append(Fact(label: key, value: items.joined(separator: ", "))) }
            default: break
            }
        }
        for edge in construct.entries[Self.edgesKey] ?? [] {
            let from = edge[Self.fromKey] ?? "", to = edge[Self.toKey] ?? ""
            let cardinality = edge["cardinality"].map { $0.isEmpty ? "" : " (\($0))" } ?? ""
            entry.facts.append(Fact(label: "Edge", value: "\(from) → \(to)\(cardinality)"))
        }
        return entry
    }

    private func frameworkEntry(_ framework: MMFramework) -> Entry {
        var entry = Entry(kind: Self.frameworks, name: framework.name, title: framework.name, definition: framework.definition, body: "")
        if !framework.area.isEmpty { entry.facts.append(Fact(label: "Area", value: framework.area)) }
        for block in framework.blocks { entry.facts.append(Fact(label: block.id, value: block.title)) }
        return entry
    }

    private func anchorEntry(_ anchor: Anchor, in m: Metamodel) -> Entry {
        var entry = Entry(kind: Self.anchors, name: anchor.name, title: anchor.title, definition: anchor.definition, body: anchor.body)
        if !anchor.appliesTo.isEmpty { entry.facts.append(Fact(label: "Applies to", value: anchor.appliesTo.joined(separator: ", "))) }
        if !anchor.aliases.isEmpty { entry.facts.append(Fact(label: "Also written", value: anchor.aliases.joined(separator: ", "))) }
        entry.reference = anchor.reference
        let types = m.types.filter { type in type.anchors.contains { m.anchor($0)?.name == anchor.name } }
        if !types.isEmpty {
            entry.groups.append(LinkGroup(title: "Types", links: types.map {
                Link(kind: Self.types, name: $0.name, title: $0.label.isEmpty ? $0.name : $0.label)
            }))
        }
        return entry
    }
}

/// The body of a metamodel page without its first level one heading, which the entry shows as its title.
enum MetaBody {
    static func withoutHeading(_ body: String) -> String {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        if let index = lines.firstIndex(where: { $0.hasPrefix("# ") }) { lines.remove(at: index) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
