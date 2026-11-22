import Foundation

extension Metamodel {
    /// The status that "agreed only" keeps. The Go dashboard hard-codes the same word, and no
    /// requirement defines "agreed" otherwise. Open debt: the metamodel does not name it.
    public static let agreedStatus = "accepted"

    /// Whether the lifecycle has an agreed status. Only pages on such a lifecycle can be agreed, so only
    /// they are hidden by "agreed only" and only their section shows a maturity bar. Issues and sources
    /// follow their own lifecycle and are never hidden.
    public static func hasAgreedStatus(_ lifecycle: [String]?) -> Bool {
        lifecycle?.contains(agreedStatus) == true
    }

    /// Whether "agreed only" hides this page: its type's lifecycle has the agreed status, and the page
    /// does not have it. This is the one rule, the UI calls it too.
    public func isHiddenWhenAgreedOnly(_ page: Page) -> Bool {
        guard let type = type(forFolder: page.ref.folder),
              Self.hasAgreedStatus(lifecycles[type.lifecycle]) else { return false }
        return page.status.lowercased() != Self.agreedStatus
    }

    /// The folder below `wiki/` of the type with this name, nil when the metamodel has no such type.
    func folder(ofType name: String) -> String? {
        type(named: name)?.folder.split(separator: "/").last.map(String.init)
    }

    /// The field that stores a relation, by the relation's name. A metamodel without the page
    /// leaves the name as the field name.
    func field(ofRelation name: String) -> String {
        relations.first { $0.name == name }?.storedField ?? name
    }
}

/// The pages the projections read: every folder of the wiki, the pages "agreed only" keeps, and the
/// lookups the Go dashboard builds per request (`newSnapshot`, `sn.folder`, `sn.byStem`).
struct ProjectionModel: Sendable {
    let metamodel: Metamodel
    let systemName: String
    /// Pages per folder in file name order.
    let byFolder: [String: [Page]]
    /// Every page, folders in name order. Ports `sn.all()`.
    let all: [Page]
    /// Page by stem, the last page wins. Ports `sn.byStem()`.
    let byStem: [String: Page]

    init(store: WikiStore, metamodel: Metamodel, agreedOnly: Bool) {
        self.metamodel = metamodel
        systemName = store.config().systemName
        var folders: [String: [Page]] = [:]
        var every: [Page] = []
        for folder in store.folders() {
            let pages = store.pages(in: folder).filter { !(agreedOnly && metamodel.isHiddenWhenAgreedOnly($0)) }
            folders[folder] = pages
            every += pages
        }
        byFolder = folders
        all = every
        var stems: [String: Page] = [:]
        for page in every { stems[page.ref.stem] = page }
        byStem = stems
    }

    /// The pages of a content type, `sn.folder(<folder of the type>)`. Empty when the metamodel lacks the type.
    func pages(ofType name: String) -> [Page] {
        metamodel.folder(ofType: name).flatMap { byFolder[$0] } ?? []
    }

    func folder(ofType name: String) -> String? { metamodel.folder(ofType: name) }

    /// The id prefix of a content type.
    func prefix(ofType name: String) -> String? {
        metamodel.type(named: name)?.prefix
    }

    func field(ofRelation name: String) -> String { metamodel.field(ofRelation: name) }

    /// Pages sorted by id, stable. Ports `SortedByID`.
    static func sortedByID(_ pages: [Page]) -> [Page] {
        pages.enumerated().sorted { a, b in
            a.element.id == b.element.id ? a.offset < b.offset : Common.less(a.element.id, b.element.id)
        }.map(\.element)
    }
}

extension Page {
    /// `MetaString`: the text of a scalar field, "" for anything else.
    func text(_ field: String) -> String {
        if case .text(let value)? = fields[field] { return value }
        return ""
    }

    /// `strings.TrimSpace(MetaString(field))`.
    func trimmed(_ field: String) -> String { Common.trim(text(field)) }

    /// `strings.ToLower(TrimSpace(MetaString(field)))`.
    func lowered(_ field: String) -> String { trimmed(field).lowercased() }

    /// The stems the field names, first use only, as `LinksOf` reads them: the items of a list, bare
    /// or linked, also nested. `exists` drops a name that is no page.
    func links(_ field: String, existing exists: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for reference in references[field] ?? [] where reference.key == nil {
            if exists(reference.name), seen.insert(reference.name).inserted { out.append(reference.name) }
        }
        return out
    }

    /// The names a field gives in order, a name that names no page included. As `AsList` then `StemOfLink`.
    func names(_ field: String) -> [String] {
        (references[field] ?? []).filter { $0.key == nil }.map(\.name)
    }

    /// `AsList` of a field read as text: a scalar is a list of one, an empty scalar a list of none.
    func textList(_ field: String) -> [String] {
        if let list = items[field] {
            return list.compactMap { if case .text(let value) = $0 { value } else { nil } }
        }
        if case .text(let value)? = fields[field], !value.isEmpty { return [value] }
        return []
    }

    /// `Entries`: the items of a field, a single value as a list of one.
    func entries(_ field: String) -> [FieldItem] {
        if let list = items[field] { return list }
        if case .text(let value)? = fields[field], !value.isEmpty { return [.text(value)] }
        return []
    }

    /// The `frOrder` rule: a number in the field, 9999 when there is none.
    func order(field: String) -> Int {
        let raw = trimmed(field)
        if let number = Int(raw) { return number }
        if let number = Double(raw), number.isFinite, abs(number) < 1e15 { return Int(number) }
        return 9999
    }

    var stem: String { ref.stem }
}
