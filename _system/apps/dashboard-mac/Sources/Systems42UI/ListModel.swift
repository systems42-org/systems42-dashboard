import Foundation
import Observation
import Systems42Kit

/// The list of the pages of one section: sort, filters and the rows they give.
/// Pages and metamodel are read through the session, so a reload reaches an existing model.
@MainActor @Observable public final class ListModel {
    /// The mode that shows plain rows. The other modes are projections the section's types declare.
    public nonisolated static let listMode = "list"
    public static let statusField = PageKey.status
    static let enumKind = "enum"

    public let sectionID: WikiSection.ID
    public var state: ListState
    /// `list`, then the projections the section's types declare and the app draws, see `ProjectionHost.modes`.
    public var modes: [String] { setup.modes }

    let session: WikiSession
    private let fallbackSection: WikiSection

    /// What the metamodel says about the section's types, read again after a reload.
    private struct Setup {
        let section: WikiSection
        let modes: [String]
        let presets: [SortPreset]
        let columns: [String]
        let enums: [(field: String, values: [String])]
        let lifecycle: [String]?
        let order: PageOrder
        /// Folders of types whose lifecycle has no agreed status: "agreed only" keeps all their pages.
        let exemptFolders: Set<String>
    }

    @ObservationIgnored private var setupCache: (revision: Int, setup: Setup)?
    @ObservationIgnored private var rowCache: (key: RowKey, rows: [Page])?

    private struct RowKey: Equatable {
        let state: ListState
        let agreedOnly: Bool
        let revision: Int
        let issueFilter: WikiSection.ID?
    }

    /// `state` is a restored one. Parts of it that name a field the types no longer have are dropped.
    public init(session: WikiSession, section: WikiSection, state: ListState? = nil) {
        self.session = session
        sectionID = section.id
        fallbackSection = section
        self.state = ListState(mode: Self.listMode)
        self.state = sanitized(state)
        if session.selectedSection == section.id { self.state.mode = session.mode }
    }

    private var setup: Setup {
        if let setupCache, setupCache.revision == session.revision { return setupCache.setup }
        let metamodel = session.metamodel
        let section = metamodel.sections.first { $0.id == sectionID } ?? fallbackSection
        let types = section.types.compactMap { metamodel.type(named: $0) }
        var declared: [String: [String]] = [:]
        var enumNames: [String] = []
        // Fields every page has come first, in the order the meta-metamodel declares them.
        let universal = metamodel.universalFields
        var columns = ([PageKey.id, PageKey.title, PageKey.status].filter { !universal.contains($0) }) + universal
        for field in types.flatMap(\.fields) {
            if !columns.contains(field.name) { columns.append(field.name) }
            guard field.kind == Self.enumKind, !field.values.isEmpty else { continue }
            if declared[field.name] == nil { enumNames.append(field.name) }
            // Types of one section that share a field name share its values, the first type's order first.
            declared[field.name, default: []] += field.values.filter { !(declared[field.name] ?? []).contains($0) }
        }
        let lifecycle = metamodel.lifecycle(of: section)
        let setup = Setup(
            section: section,
            modes: ProjectionHost.modes(for: section, metamodel: metamodel),
            presets: section.types.lazy.map { metamodel.sortPresets(for: $0) }.first { !$0.isEmpty } ?? [],
            columns: columns,
            enums: enumNames.filter { $0 != PageKey.status }.map { (field: $0, values: declared[$0] ?? []) },
            lifecycle: lifecycle,
            order: PageOrder(enums: declared, statuses: lifecycle),
            exemptFolders: Set(section.folders.filter { folder in
                !Metamodel.hasAgreedStatus(metamodel.type(forFolder: folder).flatMap { metamodel.lifecycles[$0.lifecycle] })
            })
        )
        setupCache = (session.revision, setup)
        return setup
    }

    private func sanitized(_ restored: ListState?) -> ListState {
        let first = presets.first?.keys ?? []
        var result = restored ?? ListState(sort: first, mode: Self.listMode)
        let known = Set(columns)
        if !result.sort.allSatisfy({ known.contains($0.field) }) { result.sort = first }
        let offered = Set(filterFields.map(\.field))
        result.filters = result.filters.filter { offered.contains($0.key) }
        if !modes.contains(result.mode) { result.mode = Self.listMode }
        return result
    }

    private var pages: [Page] { setup.section.folders.flatMap { session.store.pages(in: $0) } }

    public var presets: [SortPreset] { setup.presets }
    /// The fields a list can sort by: the universal fields, then every field of the section's types.
    public var columns: [String] { setup.columns }

    /// Status first, then every enum field of the section's types, with the values the metamodel declares.
    public var filterFields: [(field: String, values: [String])] {
        let setup = self.setup
        let statuses = setup.lifecycle ?? Array(Set(pages.map(\.status).filter { !$0.isEmpty })).sorted()
        return [(field: PageKey.status, values: statuses)] + setup.enums
    }

    /// The restriction to the open issues about another section, nil when there is none.
    /// The issues section shows it after the sidebar's "open" link was used.
    public var issueRestriction: String? {
        guard let about = session.issueFilter, session.metamodel.issueSection?.id == sectionID else { return nil }
        let title = session.metamodel.sections.first { $0.id == about }?.title ?? about
        return "Open issues about \(title)"
    }

    public func clearIssueRestriction() { session.clearIssueFilter() }

    /// The pages that pass the restriction and the filters, in sort order. Computed again only when
    /// the state, `agreedOnly`, the restriction or the loaded wiki change.
    public var rows: [Page] {
        let key = RowKey(
            state: state,
            agreedOnly: session.agreedOnly,
            revision: session.revision,
            issueFilter: issueRestriction == nil ? nil : session.issueFilter
        )
        if let rowCache, rowCache.key == key { return rowCache.rows }
        var candidates = pages
        if let about = key.issueFilter {
            let counted = session.openIssueIDs(of: about)
            candidates = candidates.filter { counted.contains($0.id) }
        }
        let rows = setup.order.arrange(candidates, sort: state.sort, filters: state.filters, agreedOnly: key.agreedOnly, exemptFolders: setup.exemptFolders)
        rowCache = (key, rows)
        return rows
    }

    public func value(of field: String, in page: Page) -> String {
        PageOrder.text(of: field, in: page)
    }

    /// Short values shown next to the title: the status, then the fields of the first preset.
    public func badges(of page: Page) -> [String] {
        let plain = [PageKey.id, PageKey.title, PageKey.status]
        let shown = [PageKey.status] + (presets.first?.keys.map(\.field) ?? []).filter { !plain.contains($0) }
        return shown.map { value(of: $0, in: page) }.filter { !$0.isEmpty }
    }

    /// The mode the window shows for this section: the session's while the section is selected.
    public var currentMode: String { session.selectedSection == sectionID ? session.mode : state.mode }

    /// The name of a mode in the mode switch: the projection page's label, else the page name as words.
    public func label(ofMode mode: String) -> String {
        ProjectionHost.label(ofMode: mode, metamodel: session.metamodel)
    }

    /// Shows the section in a mode, through the session so Back returns to the old one.
    public func choose(_ mode: String) {
        guard modes.contains(mode) else { return }
        session.select(mode: mode)
        state.mode = mode
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

    /// The columns the sort does not use yet.
    public var unusedColumns: [String] {
        columns.filter { column in !state.sort.contains { $0.field == column } }
    }

    /// Adds a column as the last key, ascending. A column already in the sort stays where it is.
    public func addSortKey(_ field: String) {
        guard unusedColumns.contains(field) else { return }
        state.sort.append(SortKey(field: field))
    }

    /// Puts another column in place of the key at `index`. A column already in the sort is left alone.
    public func replaceSortKey(at index: Int, with field: String) {
        guard state.sort.indices.contains(index), unusedColumns.contains(field) else { return }
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
