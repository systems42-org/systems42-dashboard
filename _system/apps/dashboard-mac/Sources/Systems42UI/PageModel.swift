import Foundation
import Observation
import Systems42Kit

/// One "follows" label of a page: its text, and the anchor it names if there is one.
public struct FollowItem: Sendable {
    public let label: String
    public let anchor: Anchor?
}

/// What one page column shows. The model is made for one page and one revision of the loaded wiki.
/// The body is rendered once, off the main thread, and kept by the session.
@MainActor @Observable public final class PageModel {
    public typealias RelationGroup = (relation: String, label: String, pages: [Page])

    /// The longest definition a popover shows.
    static let definitionLength = 300

    public let page: Page
    /// Status first, then the enum fields of the page's type. `doc` is the field's explanation in the metamodel.
    public let head: [(label: String, value: String, doc: String?)]
    /// For each head badge, what the metamodel says about its field: the doc and the allowed values. Nil when it says nothing.
    public let headHelp: [String?]
    public let outgoing: [RelationGroup]
    public let incoming: [RelationGroup]
    public let openIssues: [Page]
    /// The stems of the provenance records the page links to.
    public let sources: [String]
    /// Area, section and page title.
    public let path: [String]

    private let session: WikiSession
    private let reading: ReadingPreference
    private let revision: Int
    private var base: RenderedBody?
    @ObservationIgnored private var definitions: [PageRef: Known] = [:]
    private let render: PageRender

    /// Nil when the page is not in the loaded wiki.
    /// `render` makes the blocks of a body off the main thread. Tests pass their own.
    public init?(session: WikiSession, ref: PageRef, reading: ReadingPreference = .shared, render: @escaping PageRender = PageModel.renderBody) {
        guard let page = session.store.page(ref) else { return nil }
        let store = session.store
        let metamodel = session.metamodel
        self.session = session
        self.reading = reading
        self.render = render
        self.page = page
        revision = session.revision
        base = session.renderedPage(of: ref)

        let type = metamodel.type(forFolder: ref.folder)
        var head: [(label: String, value: String, doc: String?)] = []
        var headHelp: [String?] = []
        if !page.status.isEmpty {
            head.append((FieldLabel.text(PageKey.status), page.status, nil))
            headHelp.append(FieldHelp.text(doc: nil, values: type.flatMap { metamodel.lifecycles[$0.lifecycle] } ?? []))
        }
        for field in type?.fields ?? [] where field.kind == ListModel.enumKind && field.name != PageKey.status {
            let value = PageOrder.text(of: field.name, in: page)
            if !value.isEmpty {
                head.append((FieldLabel.text(field.name), value, field.doc))
                headHelp.append(FieldHelp.text(doc: field.doc, values: field.values))
            }
        }
        self.head = head
        self.headHelp = headHelp

        let relations = store.relations(of: ref)
        let from = store.linksFrom(ref), to = store.linksTo(ref)
        let labels = RelationLabels(metamodel: metamodel, type: type)
        outgoing = Self.groups(from, keeping: Set(relations.linksTo), labels: labels, incoming: false, store: store)
        incoming = Self.incomingGroups(to: to, from: from, wanted: Set(relations.linkedFrom + relations.traced), labels: labels, store: store)
        openIssues = store.openIssues(for: ref)

        var sources: [String] = []
        for key in page.fieldLinks.keys.sorted() {
            for link in page.fieldLinks[key] ?? [] {
                if case .source(let name) = store.resolve(link), !sources.contains(name) { sources.append(name) }
            }
        }
        self.sources = sources

        let section = metamodel.sections.first { $0.folders.contains(ref.folder) }
        path = [section?.area.label, section?.title, page.title].compactMap { $0 }
    }

    // MARK: Body

    /// The body as blocks, plain when the reader chose it. Empty until `load()` is done.
    public var rendered: RenderedPage {
        guard let base else { return RenderedPage(follows: [], blocks: []) }
        return reading.plain ? base.plain : base.normal
    }

    /// The body to draw: a first heading that repeats the title is left out, the head shows it.
    var blocks: [Block] {
        let all = rendered.blocks
        if case .heading(1, let inlines)? = all.first, String(InlineContent(inlines).text.characters) == page.title {
            return Array(all.dropFirst())
        }
        return all
    }

    public var follows: [Anchor] { followItems.compactMap(\.anchor) }

    public var followItems: [FollowItem] {
        rendered.follows.map { FollowItem(label: $0, anchor: session.metamodel.anchor($0)) }
    }

    /// Why the page is not shown as formatted, in plain words.
    public var problems: [String] { page.problems + rendered.problems }

    public var isLoading: Bool { base == nil && !isStale }

    /// True when the wiki was replaced after this model was made. A new model is needed then.
    public var isStale: Bool { revision != session.revision }

    /// The default `PageRender`: the Kit's renderer, run on the calling (background) task.
    public nonisolated static func renderBody(_ body: String, _ store: WikiStore) async -> RenderedPage {
        renderPage(body, resolve: { store.resolve($0) }, title: { name(of: $0, in: store) })
    }

    /// Renders the body off the main thread, once per page even when two models ask. A result for a
    /// replaced wiki, or for a cancelled caller, is dropped and not kept.
    public func load() async {
        guard base == nil, !isStale else { return }
        if let kept = session.renderedPage(of: page.ref) {
            base = kept
            return
        }
        let result = await session.rendering(of: page, using: render).value
        guard !Task.isCancelled, base == nil, !isStale else { return }
        session.keep(result, of: page.ref, revision: revision)
        base = result
    }

    private nonisolated static func name(of target: LinkTarget, in store: WikiStore) -> String? {
        switch target {
        case .page(let ref): store.page(ref)?.title
        case .anchor(let name), .metamodel(let name), .source(let name): name
        case .missing: nil
        }
    }

    // MARK: Links

    /// The text a popover shows for a link target: the first paragraph of a page, the definition of an anchor.
    /// Any page with a first paragraph has one. This is wider than a glossary term (FR-041).
    public func definition(for target: LinkTarget) -> String? {
        switch target {
        case .page(let ref):
            return session.store.page(ref).flatMap(definition(of:))
        case .anchor(let name):
            return session.metamodel.anchor(name).map(\.definition).flatMap { $0.isEmpty ? nil : $0 }
        case .source, .metamodel, .missing:
            return nil
        }
    }

    /// The first paragraph of a page as plain text, cut to `definitionLength`. Nil when the page has none.
    /// It comes from the rendered blocks when the session has them, else from rendering the first text paragraph alone.
    public func definition(of other: Page) -> String? {
        if let known = definitions[other.ref] { return known.text }
        let inlines: [Inline]?
        if let kept = session.renderedPage(of: other.ref) {
            inlines = kept.normal.blocks.lazy.compactMap { if case .paragraph(let inlines) = $0 { inlines } else { nil } }.first
        } else if let chunk = Self.firstTextChunk(of: other.body) {
            let store = session.store
            inlines = renderInline(chunk, resolve: { store.resolve($0) }, title: { Self.name(of: $0, in: store) })
        } else {
            inlines = nil
        }
        var line = inlines.map(Self.plainText) ?? ""
        line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let text: String? = line.isEmpty ? nil : (line.count > Self.definitionLength ? String(line.prefix(Self.definitionLength)) + "…" : line)
        definitions[other.ref] = Known(text: text)
        return text
    }

    private struct Known { let text: String? }

    /// The first part of a body that is not a heading, quote, list, table, comment or fence.
    private static func firstTextChunk(of body: String) -> String? {
        body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { text in
                guard let first = text.first else { return false }
                if "#>-|<".contains(first) || text.hasPrefix("```") || text.hasPrefix("~~~") { return false }
                if text.hasPrefix("* ") || text.hasPrefix("+ ") { return false }
                return text.range(of: "^\\d+[.)]\\s", options: .regularExpression) == nil
            }
    }

    static func plainText(_ inlines: [Inline]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let value), .code(let value): value
            case .emphasis(let inner), .strong(let inner), .link(let inner, _, _), .url(let inner, _): plainText(inner)
            }
        }.joined()
    }

    // MARK: Relations

    private static func groups(_ links: [String: [PageRef]], keeping wanted: Set<PageRef>, labels: RelationLabels, incoming: Bool, store: WikiStore) -> [RelationGroup] {
        labels.ordered(links.keys).compactMap { field in
            let pages = (links[field] ?? []).filter(wanted.contains).compactMap(store.page)
            return pages.isEmpty ? nil : (field, labels.label(of: field, incoming: incoming), pages)
        }
    }

    /// Pages that link here, then the pages of the trace panel that this page links to instead.
    private static func incomingGroups(to: [String: [PageRef]], from: [String: [PageRef]], wanted: Set<PageRef>, labels: RelationLabels, store: WikiStore) -> [RelationGroup] {
        var result = groups(to, keeping: wanted, labels: labels, incoming: true, store: store)
        var placed = Set(result.flatMap { $0.pages.map(\.ref) })
        for field in labels.ordered(from.keys) {
            let pages = (from[field] ?? []).filter { wanted.contains($0) && !placed.contains($0) }.compactMap(store.page)
            guard !pages.isEmpty else { continue }
            result.append((field, labels.label(of: field, incoming: true), pages))
            placed.formUnion(pages.map(\.ref))
        }
        let rest = wanted.subtracting(placed).compactMap(store.page).sorted { $0.id < $1.id }
        if !rest.isEmpty { result.append(("", "Linked", rest)) }
        return result
    }
}

/// The labels of relations, from the metamodel: the field name made readable. For the other end of a
/// link, the name the relation page declares as its inverse.
struct RelationLabels {
    private let metamodel: Metamodel
    private let order: [String]

    init(metamodel: Metamodel, type: MMType?) {
        self.metamodel = metamodel
        order = (type?.fields ?? []).map(\.name)
    }

    /// Fields of the page's type first, in the order the type declares them, then the others, the body last.
    func ordered<Keys: Sequence<String>>(_ fields: Keys) -> [String] {
        fields.sorted { a, b in
            func rank(_ field: String) -> Int {
                if field == WikiStore.bodyKey { return Int.max }
                return order.firstIndex(of: field) ?? order.count
            }
            return (rank(a), a) < (rank(b), b)
        }
    }

    func label(of field: String, incoming: Bool) -> String {
        if field == WikiStore.bodyKey { return incoming ? "Mentions this page" : "Mentioned in the text" }
        if incoming, let inverse = metamodel.relation(storedIn: field)?.inverse { return FieldLabel.text(inverse) }
        return FieldLabel.text(field)
    }
}
