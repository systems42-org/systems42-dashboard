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
    private var base: RenderedPage?
    @ObservationIgnored private var plainBase: RenderedPage?

    /// Nil when the page is not in the loaded wiki.
    public init?(session: WikiSession, ref: PageRef, reading: ReadingPreference = .shared) {
        guard let page = session.store.page(ref) else { return nil }
        let store = session.store
        let metamodel = session.metamodel
        self.session = session
        self.reading = reading
        self.page = page
        revision = session.revision
        base = session.renderedPage(of: ref)

        let type = metamodel.type(forFolder: ref.folder)
        var head: [(label: String, value: String, doc: String?)] = []
        if !page.status.isEmpty { head.append((FieldLabel.text(PageKey.status), page.status, nil)) }
        for field in type?.fields ?? [] where field.kind == ListModel.enumKind && field.name != PageKey.status {
            let value = PageOrder.text(of: field.name, in: page)
            if !value.isEmpty { head.append((FieldLabel.text(field.name), value, field.doc)) }
        }
        self.head = head

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
        guard reading.plain else { return base }
        if let plainBase { return plainBase }
        let plain = plainReading(base)
        plainBase = plain
        return plain
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

    /// Renders the body off the main thread. A result for a replaced wiki is dropped.
    public func load() async {
        guard base == nil, !isStale else { return }
        let body = page.body
        let store = session.store
        let result = await Task.detached(priority: .userInitiated) {
            renderPage(body, resolve: { store.resolve($0) }, title: { Self.name(of: $0, in: store) })
        }.value
        guard base == nil, !isStale else { return }
        session.keep(result, of: page.ref, revision: revision)
        plainBase = nil
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
            return session.store.page(ref).flatMap { Self.firstParagraph(of: $0.body) }
        case .anchor(let name):
            return session.metamodel.anchor(name).map(\.definition).flatMap { $0.isEmpty ? nil : $0 }
        case .source, .metamodel, .missing:
            return nil
        }
    }

    /// The first paragraph of a body that is no heading, quote, list, table or comment, as one line
    /// without emphasis marks, cut to `definitionLength`. Nil when there is none.
    static func firstParagraph(of body: String) -> String? {
        let blocks = body.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let paragraph = blocks.first(where: { text in
            guard let first = text.first else { return false }
            return !"#>-|<".contains(first) && !text.hasPrefix("* ") && !text.hasPrefix("+ ") && !text.hasPrefix("```")
        }) else { return nil }
        var line = paragraph.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        for match in Wikilink.matches(in: line).reversed() {
            var bytes = Array(line.utf8)
            bytes.replaceSubrange(match.utf8Range, with: Array((match.link.label ?? match.link.name).utf8))
            line = String(decoding: bytes, as: UTF8.self)
        }
        line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        guard !line.isEmpty else { return nil }
        return line.count > definitionLength ? String(line.prefix(definitionLength)) + "…" : line
    }

    /// The compact line under the body: each stored relation of the page with its targets as links.
    var relationLine: [Inline] {
        var inlines: [Inline] = []
        for group in outgoing where group.relation != WikiStore.bodyKey {
            if !inlines.isEmpty { inlines.append(.text("  ·  ")) }
            inlines.append(.text(group.label + " "))
            for (index, target) in group.pages.enumerated() {
                if index > 0 { inlines.append(.text(", ")) }
                inlines.append(.link([.text(target.id)], .page(target.ref), raw: target.id))
            }
        }
        return inlines
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

/// The labels of relations, from the metamodel: a relation page's label or title, else the field name made readable.
/// For the other end of a link the relation's inverse is used when the page names one.
struct RelationLabels {
    private static let labelKey = "label", inverseKey = "inverse", fieldKey = "field"

    private let relations: [MMConstruct]
    private let order: [String]

    init(metamodel: Metamodel, type: MMType?) {
        relations = metamodel.relations
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
        let relation = relations.first { $0.frontmatter[Self.fieldKey] == .text(field) } ?? relations.first { $0.name == field }
        func text(_ key: String) -> String? {
            guard case .text(let value)? = relation?.frontmatter[key], !value.isEmpty else { return nil }
            return value
        }
        if let declared = text(Self.labelKey) ?? text(PageKey.title) { return declared }
        if incoming, let inverse = text(Self.inverseKey) { return FieldLabel.text(inverse) }
        return FieldLabel.text(field)
    }
}
