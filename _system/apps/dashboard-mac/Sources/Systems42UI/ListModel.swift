import Foundation
import Observation
import Systems42Kit

/// The list of the pages of one section: sort, filters and the rows they give.
@MainActor @Observable public final class ListModel {
    /// The mode that shows plain rows. Projection modes come with later issues.
    public static let listMode = "list"
    public static let statusField = UniversalField.status
    private static let enumKind = "enum"

    public let sectionID: WikiSection.ID
    public var state: ListState
    public let presets: [SortPreset]
    /// Status first, then every enum field of the section's types, with the values the metamodel declares.
    public let filterFields: [(field: String, values: [String])]
    /// The fields a list can sort by: id, title, status and every field of the section's types.
    public let columns: [String]
    public let modes: [String] = [ListModel.listMode]

    private let session: WikiSession
    private let pages: [Page]
    private let order: PageOrder
    @ObservationIgnored private var cache: (state: ListState, agreedOnly: Bool, rows: [Page])?

    /// `state` is a restored one. Parts of it that name a field the types no longer have are dropped.
    public init(session: WikiSession, section: WikiSection, state: ListState? = nil) {
        self.session = session
        sectionID = section.id
        let metamodel = session.metamodel
        let types = section.types.compactMap { metamodel.type(named: $0) }
        pages = section.folders.flatMap { session.store.pages(in: $0) }
        presets = section.types.lazy.map { metamodel.sortPresets(for: $0) }.first { !$0.isEmpty } ?? []

        var declared: [String: [String]] = [:]
        var fieldNames: [String] = [UniversalField.id, UniversalField.title, UniversalField.status]
        var enumNames: [String] = []
        for field in types.flatMap(\.fields) {
            if !fieldNames.contains(field.name) { fieldNames.append(field.name) }
            guard field.kind == Self.enumKind, !field.values.isEmpty else { continue }
            if declared[field.name] == nil { enumNames.append(field.name) }
            // Types of one section that share a field name share its values, the first type's order first.
            declared[field.name, default: []] += field.values.filter { !(declared[field.name] ?? []).contains($0) }
        }
        let lifecycle = metamodel.lifecycle(of: section)
        let statuses = lifecycle ?? Array(Set(pages.map(\.status).filter { !$0.isEmpty })).sorted()
        columns = fieldNames
        order = PageOrder(enums: declared, statuses: lifecycle)
        let filterFields = [(field: UniversalField.status, values: statuses)]
            + enumNames.filter { $0 != UniversalField.status }.map { (field: $0, values: declared[$0] ?? []) }
        self.filterFields = filterFields

        let first = presets.first?.keys ?? []
        var restored = state ?? ListState(sort: first, mode: Self.listMode)
        let known = Set(fieldNames)
        if !restored.sort.allSatisfy({ known.contains($0.field) }) { restored.sort = first }
        restored.filters = restored.filters.filter { name, _ in filterFields.contains { $0.field == name } }
        if restored.mode != Self.listMode { restored.mode = Self.listMode }
        self.state = restored
    }

    /// The pages that pass the filters, in sort order. Computed again only when state or `agreedOnly` change.
    public var rows: [Page] {
        let agreedOnly = session.agreedOnly
        if let cache, cache.state == state, cache.agreedOnly == agreedOnly { return cache.rows }
        let rows = order.arrange(pages, sort: state.sort, filters: state.filters, agreedOnly: agreedOnly)
        cache = (state, agreedOnly, rows)
        return rows
    }

    public func value(of field: String, in page: Page) -> String {
        PageOrder.text(of: field, in: page)
    }

    /// Short values shown next to the title: the status, then the fields of the first preset.
    public func badges(of page: Page) -> [String] {
        let shown = [UniversalField.status]
            + (presets.first?.keys.map(\.field) ?? []).filter { ![UniversalField.id, UniversalField.title, UniversalField.status].contains($0) }
        return shown.map { value(of: $0, in: page) }.filter { !$0.isEmpty }
    }

    public var hasFilters: Bool { !state.filters.isEmpty }

    // MARK: Editing the state

    public func apply(preset: SortPreset) { state.sort = preset.keys }

    public func toggleFilter(field: String, value: String) {
        var chosen = state.filters[field] ?? []
        if !chosen.insert(value).inserted { chosen.remove(value) }
        state.filters[field] = chosen.isEmpty ? nil : chosen
    }

    public func clearFilters() { state.filters = [:] }

    /// Adds a column as the last key, ascending. A column already in the sort stays where it is.
    public func addSortKey(_ field: String) {
        guard columns.contains(field), !state.sort.contains(where: { $0.field == field }) else { return }
        state.sort.append(SortKey(field: field))
    }

    /// Puts another column in place of the key at `index`. A column already in the sort is left alone.
    public func replaceSortKey(at index: Int, with field: String) {
        guard state.sort.indices.contains(index), columns.contains(field),
              !state.sort.contains(where: { $0.field == field }) else { return }
        state.sort[index] = SortKey(field: field, ascending: state.sort[index].ascending)
    }

    public func toggleDirection(at index: Int) {
        guard state.sort.indices.contains(index) else { return }
        state.sort[index].ascending.toggle()
    }

    public func removeSortKey(at index: Int) {
        guard state.sort.indices.contains(index) else { return }
        state.sort.remove(at: index)
    }

    // MARK: Selection

    public var selectedPage: PageRef? { session.selectedPage }

    /// Selects a page through the session, so history stays right.
    public func select(_ ref: PageRef) { session.select(page: ref) }
}
