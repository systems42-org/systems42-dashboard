import Foundation

/// One entry of the search index: the fields of one record of the dashboard's `/search.json`
/// (`BuildRecords` in `_system/apps/dashboard/internal/search/search.go`), without its `url`: the
/// route of the page in the web dashboard. The Mac app opens pages by `ref`.
public struct SearchEntry: Codable, Sendable, Equatable {
    public var id: String
    /// The label of the page type, as the metamodel names it.
    public var type: String
    public var title: String
    public var status: String
    public var aliases: [String]
    /// The reader-visible text of the page body, one paragraph or list item per line.
    public var plain: String
    /// The lower-case values of the fields the search looks at, by field name.
    public var fields: [String: [String]]
    /// The ids of the pages this page links to or is linked from, sorted.
    public var links: [String]
    /// Where the page lives. Not part of the dashboard's JSON.
    public var ref: PageRef?

    public init(
        id: String, type: String, title: String, status: String = "", aliases: [String] = [],
        plain: String = "", fields: [String: [String]] = [:], links: [String] = [], ref: PageRef? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.status = status
        self.aliases = aliases
        self.plain = plain
        self.fields = fields
        self.links = links
        self.ref = ref
    }

    private enum CodingKeys: String, CodingKey { case id, type, title, status, aliases, plain, fields, links }

    /// Like the ranker in JavaScript, a missing `aliases`, `fields` or `links` is empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            type: try c.decode(String.self, forKey: .type),
            title: try c.decode(String.self, forKey: .title),
            status: try c.decodeIfPresent(String.self, forKey: .status) ?? "",
            aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            plain: try c.decodeIfPresent(String.self, forKey: .plain) ?? "",
            fields: try c.decodeIfPresent([String: [String]].self, forKey: .fields) ?? [:],
            links: try c.decodeIfPresent([String].self, forKey: .links) ?? []
        )
    }
}

/// A value of a filter drop-down and the way the wiki writes it (FR-009).
public struct SearchFilterOption: Sendable, Equatable {
    public let value: String
    public let label: String
}

/// The choices of the status, priority and tag filters (`Filters` in search.go).
public struct SearchFilterOptions: Sendable, Equatable {
    public let statuses, priorities, tags: [SearchFilterOption]
}

/// The names the search takes from the page fields. They come from the dashboard, not from the
/// metamodel: `SearchFields` in search.go says which fields are indexed as words (FR-006), and the
/// priority and tag filters of search-rank.js (`filter`) look at `fields.priority` and `fields.tags`.
enum SearchFields {
    /// search.go `SearchFields`.
    static let indexed = ["tags", "status", "stereotype", "notation", "level", "priority", "kind", "state", "category", "dimensions"]
    static let tags = "tags", priority = "priority", status = "status"
    /// search.go `priorityOrder`: the order of the priority filter. Other values follow, sorted.
    static let priorityOrder = ["must", "should", "could", "wont", "won't"]
    /// The type whose pages are the glossary: their titles and aliases are the synonym groups (FR-003).
    /// Like `issue` and `source` in `RelationRules`, a type the code treats specially.
    static let glossaryType = "domain-term"
}

/// The search index of a wiki: what the dashboard serves as `/search.json`, built from the pages
/// in the store (FR-001). Encoded, it is that JSON.
public struct SearchIndex: Sendable, Codable {
    public let entries: [SearchEntry]
    /// Glossary term groups: the title and the aliases of each term, lower-case (FR-003).
    public let synonyms: [[String]]
    /// The choices of the status, priority and tag filters. Not part of the dashboard's JSON.
    public let filterOptions: SearchFilterOptions
    let prepared: PreparedIndex

    private enum CodingKeys: String, CodingKey { case entries = "records", synonyms }

    public init(entries: [SearchEntry], synonyms: [[String]]) {
        self.init(entries: entries, synonyms: synonyms, filterOptions: Self.filterOptions(of: entries))
    }

    private init(entries: [SearchEntry], synonyms: [[String]], filterOptions: SearchFilterOptions) {
        self.entries = entries
        self.synonyms = synonyms
        self.filterOptions = filterOptions
        self.prepared = PreparedIndex(entries: entries, synonyms: synonyms)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try c.decode([SearchEntry].self, forKey: .entries),
                  synonyms: try c.decodeIfPresent([[String]].self, forKey: .synonyms) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entries, forKey: .entries)
        try c.encode(synonyms, forKey: .synonyms)
    }

    /// Builds the index of all pages of the store, in folder order (search.go `BuildIndex`).
    public init(store: WikiStore, metamodel: Metamodel) {
        let folders = store.folders()
        let pages = folders.flatMap { store.pages(in: $0) }
        let names = store.linkNames()
        var titles: [String: String] = [:]
        for page in pages { titles[page.ref.stem] = page.title }
        let context = PlainText.Context(titles: titles, names: names)
        let neighbours = Self.neighbourLinks(pages, names: names)

        var labels: [String: String] = [:]
        for folder in folders { labels[folder] = metamodel.type(forFolder: folder)?.label ?? folder }
        let entries = pages.map { page in
            SearchEntry(
                id: page.id, type: labels[page.ref.folder] ?? page.ref.folder, title: page.title, status: page.status,
                aliases: page.aliases, plain: PlainText.plain(body: page.body, context: context),
                fields: Self.fields(of: page), links: neighbours[page.id] ?? [], ref: page.ref
            )
        }
        var groups: [[String]] = []
        if let glossary = metamodel.type(named: SearchFields.glossaryType) {
            for page in store.pages(in: Self.lastComponent(glossary.folder)) {
                var group: [String] = []
                let title = Search.goLowercased(page.title.trimmingCharacters(in: .whitespacesAndNewlines))
                if !title.isEmpty { group.append(title) }
                for alias in page.aliases {
                    let a = Search.goLowercased(alias.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !a.isEmpty { group.append(a) }
                }
                groups.append(group)
            }
        }
        self.init(entries: entries, synonyms: groups, filterOptions: Self.filterOptions(of: pages))
    }

    private static func lastComponent(_ folder: String) -> String {
        folder.split(separator: "/").last.map(String.init) ?? folder
    }

    /// search.go `fieldsOf`.
    private static func fields(of page: Page) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for key in SearchFields.indexed {
            let values = writtenValues(page, key).map { Search.goLowercased($0) }.filter { !$0.isEmpty }
            if !values.isEmpty { out[key] = values }
        }
        return out
    }

    /// The trimmed, non-empty values of a field as the wiki writes them.
    private static func writtenValues(_ page: Page, _ key: String) -> [String] {
        let items: [String]
        switch page.fields[key] {
        case .text(let text)?: items = [text]
        case .list(let list)?: items = list
        default: items = []
        }
        return items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// search.go `neighbourLinks`: the ids of the pages a page links to and of those that link to it.
    /// A link finds its page by stem or id, as the dashboard does, and not by alias.
    private static func neighbourLinks(_ pages: [Page], names: Names) -> [String: [String]] {
        var stemOf: [String: String] = [:]
        var pageByStem: [String: Page] = [:]
        for page in pages {
            if stemOf[page.ref.stem] == nil { stemOf[page.ref.stem] = page.ref.stem }
            if stemOf[page.id] == nil { stemOf[page.id] = page.ref.stem }
            pageByStem[page.ref.stem] = page
        }
        var sets: [String: Set<String>] = [:]
        for page in pages where sets[page.id] == nil { sets[page.id] = [] }
        for page in pages {
            let links = page.fieldLinks.values.flatMap { $0 } + page.bodyLinks
            for link in links {
                let name = link.name
                if names.isSource(target: link.target, name: name) || name == page.ref.stem || name == page.id { continue }
                guard let stem = stemOf[name], let other = pageByStem[stem], other.id != page.id else { continue }
                sets[page.id, default: []].insert(other.id)
                sets[other.id, default: []].insert(page.id)
            }
        }
        return sets.mapValues { $0.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } }
    }

    /// search.go `Filters`: the first spelling seen for each lower-case value.
    private static func filterOptions(of pages: [Page]) -> SearchFilterOptions {
        func options(_ key: String, order: [String] = []) -> [SearchFilterOption] {
            var first: [String: String] = [:]
            for page in pages {
                for written in writtenValues(page, key) {
                    let low = Search.goLowercased(written)
                    if first[low] == nil { first[low] = written }
                }
            }
            return sortedOptions(first, order: order)
        }
        return SearchFilterOptions(
            statuses: options(SearchFields.status), priorities: options(SearchFields.priority, order: SearchFields.priorityOrder),
            tags: options(SearchFields.tags)
        )
    }

    /// The options of a list of entries, which keep only the lower-case values.
    private static func filterOptions(of entries: [SearchEntry]) -> SearchFilterOptions {
        func options(_ values: [String], order: [String] = []) -> [SearchFilterOption] {
            sortedOptions(Dictionary(values.map { ($0, $0) }, uniquingKeysWith: { first, _ in first }), order: order)
        }
        return SearchFilterOptions(
            statuses: options(entries.flatMap { $0.fields[SearchFields.status] ?? [] }),
            priorities: options(entries.flatMap { $0.fields[SearchFields.priority] ?? [] }, order: SearchFields.priorityOrder),
            tags: options(entries.flatMap { $0.fields[SearchFields.tags] ?? [] })
        )
    }

    private static func sortedOptions(_ labels: [String: String], order: [String]) -> [SearchFilterOption] {
        labels.keys.sorted { a, b in
            let ra = order.firstIndex(of: a), rb = order.firstIndex(of: b)
            if (ra == nil) != (rb == nil) { return ra != nil }
            if let ra, let rb, ra != rb { return ra < rb }
            return a.utf8.lexicographicallyPrecedes(b.utf8)
        }.map { SearchFilterOption(value: $0, label: labels[$0] ?? $0) }
    }
}
