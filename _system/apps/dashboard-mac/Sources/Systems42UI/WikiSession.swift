import Foundation
import Observation
import Systems42Kit

/// A wiki read once: everything `WikiSession` needs, built off the main thread.
/// `WikiStore` is `@unchecked Sendable` in the Kit and guards its state with a lock.
struct LoadedWiki: Sendable {
    let config: WikiConfig
    let store: WikiStore
    let metamodel: Metamodel
    let figures: [String: SectionFigures]
    let orientation: Orientation?

    init(root: WikiRoot) {
        self.init(root: root, store: WikiStore(root: root))
    }

    /// Reads the wiki again for a refresh. Pages whose files did not change are not parsed again.
    init(root: WikiRoot, reusing previous: WikiStore, changed: [URL]) {
        self.init(root: root, store: WikiStore(root: root, reusing: previous, changed: changed))
    }

    private init(root: WikiRoot, store: WikiStore) {
        // One snapshot gives the pages and the metamodel, so the wiki is read once.
        let metamodel = store.metamodel
        var figures: [String: SectionFigures] = [:]
        for section in metamodel.sections {
            var found = SectionFigures()
            var issues = Set<String>()
            for folder in section.folders {
                let subject = Metamodel.hasAgreedStatus(metamodel.type(forFolder: folder).flatMap { metamodel.lifecycles[$0.lifecycle] })
                for page in store.pages(in: folder) {
                    found.add(status: page.status.lowercased(), keptByAgreedOnly: !subject || page.status.lowercased() == Metamodel.agreedStatus)
                    issues.formUnion(store.openIssues(for: page.ref).map(\.id))
                }
            }
            found.openIssueIDs = issues
            figures[section.id] = found
        }
        self.config = WikiConfig.load(root)
        self.store = store
        self.metamodel = metamodel
        self.figures = figures
        self.orientation = Self.vision(in: store, metamodel: metamodel)
    }

    /// The field that holds the stereotype of a page.
    private static let stereotypeField = "stereotype"
    /// The stereotype of the vision. The metamodel says "exactly one vision per wiki" in prose only.
    private static let visionStereotype = "vision"

    /// The first page with the vision stereotype, with its first plain paragraph.
    /// Only types that list the stereotype are searched.
    private static func vision(in store: WikiStore, metamodel: Metamodel) -> Orientation? {
        func same(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == visionStereotype }
        for type in metamodel.types where type.stereotypes.contains(where: same) {
            guard let folder = type.folder.split(separator: "/").last else { continue }
            for page in store.pages(in: String(folder)) {
                guard case .text(let value)? = page.fields[stereotypeField], same(value) else { continue }
                let paragraph = page.body.components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty && !["#", ">", "-", "|", "<"].contains(String($0.first!)) } ?? ""
                return Orientation(title: page.title, text: paragraph.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " "), ref: page.ref)
            }
        }
        return nil
    }
}

/// The observable model of one open wiki: what the window shows and where the reader is.
@MainActor @Observable public final class WikiSession {
    public let root: WikiRoot
    public private(set) var config: WikiConfig
    public private(set) var store: WikiStore
    public private(set) var metamodel: Metamodel
    public var selectedSection: WikiSection.ID?
    public var selectedPage: PageRef?
    /// Show only agreed pages in the counts.
    public var agreedOnly = false
    /// The section whose open issues the issues list is limited to. Part of the history place, so
    /// Back and Forward restore it. Set by `showIssues(of:)`, cleared by `clearIssueFilter()`.
    public private(set) var issueFilter: WikiSection.ID?

    /// The search whose full result list the list column shows, nil when it shows a section.
    /// Part of the history place, so Back and Forward restore it.
    public private(set) var shownSearch: SearchRequest?

    /// How the list column shows the selected section: `list`, or a projection the section offers.
    /// Part of the history place, so Back and Forward restore it.
    public private(set) var mode = ListModel.listMode

    /// Whether the list column shows a projection and no search results: it then takes the width of list and page.
    public var showsProjection: Bool {
        shownSearch == nil && selectedSection != nil && ProjectionHost.nativeProjections.contains(mode)
    }

    private var figures: [String: SectionFigures]
    public private(set) var orientation: Orientation?
    /// Counts up each time the loaded wiki is replaced, so models know their rows are stale.
    public private(set) var revision = 0
    /// Rendered page bodies of the current revision. A replaced wiki empties it.
    @ObservationIgnored private var renderedPages: [PageRef: RenderedBody] = [:]
    /// Renders that are running, so a page is rendered once however many models ask for it.
    @ObservationIgnored private var running: [PageRef: Task<RenderedBody, Never>] = [:]
    private static let mostRenderedPages = 100
    /// What the folder watcher and the refresh need. See `WikiSession+Refresh.swift`.
    @ObservationIgnored var watcher: FileWatcher?
    @ObservationIgnored var refreshing: Task<Void, Never>?
    /// Tests set it to hold a refresh before it reads.
    @ObservationIgnored var beforeReading: (@MainActor ([URL]) async -> Void)?
    @ObservationIgnored var changesWaiting: Set<URL> = []
    /// The parts of a wiki folder that are gone, nil while the folder is whole. The window then
    /// shows the same view as for a folder that is not a wiki.
    public internal(set) var missingParts: [String]?
    @ObservationIgnored fileprivate var explainerModel: MetamodelModel?
    @ObservationIgnored var tourModelStore: TourModel?
    @ObservationIgnored var searchModelStore: SearchModel?
    @ObservationIgnored var projectionsModelStore: ProjectionsModel?
    @ObservationIgnored var termNetworkModelStore: TermNetworkModel?
    /// The mode the section was last shown in, so a section comes back as the reader left it.
    private var rememberedModes: [WikiSection.ID: String] = [:]
    private var history: [Place] = []
    private var position = -1

    private static let longestHistory = 100

    private struct Place: Equatable {
        let section: WikiSection.ID?
        let page: PageRef?
        /// The section whose open issues the issues list is limited to, nil for all issues.
        var issuesAbout: WikiSection.ID?
        /// The search whose results the list column shows, nil for a section.
        var search: SearchRequest?
        /// How the section is shown, `list` or a projection.
        var mode = ListModel.listMode
    }

    init(loaded: LoadedWiki, root: WikiRoot) {
        self.root = root
        config = loaded.config
        store = loaded.store
        metamodel = loaded.metamodel
        figures = loaded.figures
        orientation = loaded.orientation
    }

    /// Swaps in a freshly read wiki. Models read through the session, so they follow on their next read.
    func replace(with loaded: LoadedWiki) {
        config = loaded.config
        store = loaded.store
        metamodel = loaded.metamodel
        figures = loaded.figures
        orientation = loaded.orientation
        renderedPages = [:]
        running = [:]
        revision += 1
        if let id = selectedSection, !offers(mode, in: id) { mode = ListModel.listMode }
    }

    /// The rendered body of a page, if it was rendered for the current wiki.
    func renderedPage(of ref: PageRef) -> RenderedBody? {
        renderedPages[ref]
    }

    /// Keeps a rendered body. A result of an older revision is dropped.
    func keep(_ body: RenderedBody, of ref: PageRef, revision: Int) {
        guard revision == self.revision else { return }
        if renderedPages.count >= Self.mostRenderedPages { renderedPages = [:] }
        renderedPages[ref] = body
        running[ref] = nil
    }

    /// The render of a page. A second ask while it runs gets the same task, so `render` runs once.
    /// The task runs off the main actor and also makes the plain form.
    func rendering(of page: Page, using render: @escaping PageRender) -> Task<RenderedBody, Never> {
        if let task = running[page.ref] { return task }
        let body = page.body, store = self.store
        let task = Task.detached(priority: .userInitiated) {
            let normal = await render(body, store)
            return RenderedBody(normal: normal, plain: plainReading(normal))
        }
        running[page.ref] = task
        return task
    }

    /// Reads the wiki on the calling thread. The app uses `open(_:)` instead.
    public convenience init(root: WikiRoot) {
        self.init(loaded: LoadedWiki(root: root), root: root)
    }

    /// Reads the wiki off the main thread and returns the session on it.
    public static func open(_ root: WikiRoot) async -> WikiSession {
        let loaded = await Task.detached { LoadedWiki(root: root) }.value
        return WikiSession(loaded: loaded, root: root)
    }

    public var title: String { config.systemName }

    /// "<Section title> · <count>", nil while no section is selected.
    public var subtitle: String? {
        guard let id = selectedSection,
              let row = sidebar.lazy.flatMap(\.rows).first(where: { $0.section.id == id }) else { return nil }
        return "\(row.section.title) · \(row.count)"
    }

    public var sidebar: [SidebarGroup] {
        Area.allCases.compactMap { area in
            let rows = metamodel.sections.filter { $0.area == area }.map(row)
            return rows.isEmpty ? nil : SidebarGroup(area: area, rows: rows)
        }
    }

    private func row(_ section: WikiSection) -> SidebarRow {
        let all = figures[section.id] ?? SectionFigures()
        let lifecycle = metamodel.lifecycle(of: section)
        let ordered = all.ordered(by: lifecycle)
        let shown = agreedOnly ? all.keptByAgreedOnly(in: ordered) : ordered
        return SidebarRow(
            section: section,
            count: shown.reduce(0) { $0 + $1.count },
            byStatus: shown,
            openIssues: all.openIssues,
            agreedShare: all.count == 0 ? 0 : Double(all.agreed) / Double(all.count),
            showsMaturity: Metamodel.hasAgreedStatus(lifecycle)
        )
    }

    /// Selects the section and page a link points at. Other targets and missing pages do nothing.
    public func open(_ target: LinkTarget) {
        guard case .page(let ref) = target, store.page(ref) != nil else { return }
        let id = section(of: ref)?.id
        go(to: Place(section: id, page: ref, mode: modeShown(in: id)))
    }

    /// The ids of the open issues that point at a page of the section, as the sidebar counts them.
    func openIssueIDs(of section: WikiSection.ID) -> Set<String> {
        figures[section]?.openIssueIDs ?? []
    }

    /// Shows all issues again, and records the place.
    public func clearIssueFilter() {
        guard issueFilter != nil else { return }
        go(to: Place(section: selectedSection, page: selectedPage, mode: modeShown(in: selectedSection)))
    }

    /// Opens the issues section, filtered to the issues that point at `section`.
    public func showIssues(of section: WikiSection.ID) {
        guard let issues = metamodel.issueSection else { return }
        go(to: Place(section: issues.id, page: nil, issuesAbout: section, mode: modeShown(in: issues.id)))
    }

    /// Leaves the result list, back to the pages of the section. Records the place.
    public func closeSearch() {
        guard shownSearch != nil else { return }
        go(to: Place(section: selectedSection, page: selectedPage, mode: modeShown(in: selectedSection)))
    }

    /// Shows the full result list of a search, and records the place.
    public func showSearch(_ request: SearchRequest) {
        go(to: Place(section: selectedSection, page: nil, search: request, mode: mode))
    }

    /// Changes the filter of the shown search. The place in the history changes with it, no new place is recorded.
    func refineSearch(_ request: SearchRequest) {
        guard shownSearch != nil, history.indices.contains(position) else { return }
        history[position].search = request
        shownSearch = request
    }

    /// Selects a page of the shown results and keeps the results, so Back returns to the list.
    /// Without a shown search it does nothing.
    public func selectResult(_ ref: PageRef) {
        guard let search = shownSearch, store.page(ref) != nil else { return }
        let id = section(of: ref)?.id
        go(to: Place(section: id, page: ref, search: search, mode: modeShown(in: id)))
    }

    /// Shows a place without recording it in the history. Only the tour uses it. A page that does
    /// not exist, or a section the wiki lacks, shows nothing.
    func showUnrecorded(section: WikiSection.ID?, page: PageRef?) {
        let section = section.flatMap { id in metamodel.sections.contains { $0.id == id } ? id : nil }
        let page = page.flatMap { store.page($0) == nil ? nil : $0 }
        // The mode stays what the section is shown in, so a tour step never changes the remembered mode.
        restore(Place(section: section, page: page, issuesAbout: nil, mode: modeShown(in: section)), remember: false)
    }

    /// The number of places in the history.
    var historyCount: Int { history.count }

    /// Shows a section with no page chosen, and records the place. The one way to change section.
    public func select(section id: WikiSection.ID?) {
        guard let id else { return }
        go(to: Place(section: id, page: nil, mode: modeShown(in: id)))
    }

    /// Shows the selected section as a list or as a projection it offers, and records the place.
    /// A mode the section does not offer, and a mode while search results show, do nothing.
    public func select(mode newMode: String) {
        guard shownSearch == nil, let id = selectedSection, offers(newMode, in: id) else { return }
        go(to: Place(section: id, page: selectedPage, issuesAbout: issueFilter, mode: newMode))
    }

    /// Takes a mode the window stored for a section, without a new place. It only fills in a section that
    /// was not shown in a mode yet, so what the reader chose in this window wins.
    func adopt(mode stored: String, in id: WikiSection.ID) {
        guard stored != ListModel.listMode, rememberedModes[id] == nil, offers(stored, in: id) else { return }
        rememberedModes[id] = stored
        guard selectedSection == id, shownSearch == nil, mode == ListModel.listMode else { return }
        mode = stored
        if history.indices.contains(position) { history[position].mode = stored }
    }

    /// Selects the page of an element of a projection. The section and the mode stay, only the page changes,
    /// so the inspector may show a page of any section. Without a projection it selects like `select(page:)`.
    public func selectInProjection(_ ref: PageRef) {
        guard store.page(ref) != nil else { return }
        guard showsProjection else { select(page: ref); return }
        go(to: Place(section: selectedSection, page: ref, issuesAbout: issueFilter, mode: mode))
    }

    /// Closes the page that shows next to a projection. Records the place.
    public func deselectPage() {
        guard selectedPage != nil else { return }
        go(to: Place(section: selectedSection, page: nil, issuesAbout: issueFilter, search: shownSearch, mode: mode))
    }

    /// Whether the section offers the mode.
    private func offers(_ mode: String, in id: WikiSection.ID) -> Bool {
        guard let section = metamodel.sections.first(where: { $0.id == id }) else { return mode == ListModel.listMode }
        return ProjectionHost.modes(for: section, metamodel: metamodel).contains(mode)
    }

    /// The mode a section shows when the reader goes there: the one it has now, or the one it had last.
    private func modeShown(in id: WikiSection.ID?) -> String {
        guard let id else { return ListModel.listMode }
        let wanted = id == selectedSection ? mode : rememberedModes[id] ?? ListModel.listMode
        return offers(wanted, in: id) ? wanted : ListModel.listMode
    }

    /// Selects a page of the wiki and records the place. A page that does not exist does nothing.
    public func select(page ref: PageRef) {
        guard store.page(ref) != nil else { return }
        let id = section(of: ref)?.id
        // Picking a page of the restricted issues list keeps the restriction.
        go(to: Place(section: id, page: ref, issuesAbout: id == selectedSection ? issueFilter : nil, mode: modeShown(in: id)))
    }

    public func back() {
        guard position > 0 else { return }
        position -= 1
        restore(history[position], remember: true)
    }

    public func forward() {
        guard position + 1 < history.count else { return }
        position += 1
        restore(history[position], remember: true)
    }

    private func section(of ref: PageRef) -> WikiSection? {
        metamodel.sections.first { $0.folders.contains(ref.folder) }
    }

    private func go(to place: Place) {
        // A place the tour showed without recording differs from the recorded one, so it is recorded.
        if position >= 0, history[position] == place,
           place == Place(section: selectedSection, page: selectedPage, issuesAbout: issueFilter, search: shownSearch, mode: mode) { return }
        history = Array(history.prefix(position + 1)) + [place]
        if history.count > Self.longestHistory { history.removeFirst(history.count - Self.longestHistory) }
        position = history.count - 1
        restore(place, remember: true)
    }

    private func restore(_ wanted: Place, remember: Bool) {
        // A mode the section does not offer now (the wiki was reloaded) shows the list.
        var place = wanted
        if let id = place.section, !offers(place.mode, in: id) { place.mode = ListModel.listMode }
        if remember, let id = place.section { rememberedModes[id] = place.mode }
        mode = place.mode
        selectedSection = place.section
        selectedPage = place.page
        issueFilter = place.issuesAbout
        shownSearch = place.search
    }
}

/// What the user asked the search for: the words and the filter. The list column shows its results.
public struct SearchRequest: Equatable, Sendable {
    public let query: String
    public let filter: SearchFilter

    public init(query: String, filter: SearchFilter) {
        self.query = query
        self.filter = filter
    }
}

/// A page body rendered both ways: with links, and for plain reading (FR-049).
struct RenderedBody: Equatable, Sendable {
    let normal: RenderedPage
    let plain: RenderedPage
}

/// Makes the blocks of a page body. It runs off the main actor.
public typealias PageRender = @Sendable (_ body: String, _ store: WikiStore) async -> RenderedPage

extension WikiSession {
    /// The model of the Metamodel window of this wiki. One per session, so a window and the links that open it share their selection.
    public var explainer: MetamodelModel {
        if let model = explainerModel { return model }
        let model = MetamodelModel(session: self)
        explainerModel = model
        return model
    }
}

extension WikiSession {
    /// The search of this wiki. One per session, so the window and the menu share it.
    public var search: SearchModel {
        if let model = searchModelStore { return model }
        let model = SearchModel(session: self)
        searchModelStore = model
        return model
    }
}
