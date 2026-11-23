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
        let store = WikiStore(root: root)
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
                return Orientation(title: page.title, text: paragraph.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " "))
            }
        }
        return nil
    }
}

/// The observable model of one open wiki: what the window shows and where the reader is.
@MainActor @Observable public final class WikiSession {
    public let root: WikiRoot
    public let config: WikiConfig
    public private(set) var store: WikiStore
    public private(set) var metamodel: Metamodel
    public var selectedSection: WikiSection.ID?
    public var selectedPage: PageRef?
    /// Show only agreed pages in the counts.
    public var agreedOnly = false
    /// The section whose open issues the issues list is limited to. Part of the history place, so
    /// Back and Forward restore it. Set by `showIssues(of:)`, cleared by `clearIssueFilter()`.
    public private(set) var issueFilter: WikiSection.ID?

    private var figures: [String: SectionFigures]
    public private(set) var orientation: Orientation?
    /// Counts up each time the loaded wiki is replaced, so models know their rows are stale.
    public private(set) var revision = 0
    /// Rendered page bodies of the current revision. A replaced wiki empties it.
    @ObservationIgnored private var renderedPages: [PageRef: RenderedBody] = [:]
    /// Renders that are running, so a page is rendered once however many models ask for it.
    @ObservationIgnored private var running: [PageRef: Task<RenderedBody, Never>] = [:]
    private static let mostRenderedPages = 100
    @ObservationIgnored fileprivate var explainerModel: MetamodelModel?
    @ObservationIgnored var tourModelStore: TourModel?
    private var history: [Place] = []
    private var position = -1

    private static let longestHistory = 100

    private struct Place: Equatable {
        let section: WikiSection.ID?
        let page: PageRef?
        /// The section whose open issues the issues list is limited to, nil for all issues.
        var issuesAbout: WikiSection.ID?
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
        store = loaded.store
        metamodel = loaded.metamodel
        figures = loaded.figures
        orientation = loaded.orientation
        renderedPages = [:]
        running = [:]
        revision += 1
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
        go(to: Place(section: section(of: ref)?.id, page: ref))
    }

    /// The ids of the open issues that point at a page of the section, as the sidebar counts them.
    func openIssueIDs(of section: WikiSection.ID) -> Set<String> {
        figures[section]?.openIssueIDs ?? []
    }

    /// Shows all issues again, and records the place.
    public func clearIssueFilter() {
        guard issueFilter != nil else { return }
        go(to: Place(section: selectedSection, page: selectedPage))
    }

    /// Opens the issues section, filtered to the issues that point at `section`.
    public func showIssues(of section: WikiSection.ID) {
        guard let issues = metamodel.issueSection else { return }
        go(to: Place(section: issues.id, page: nil, issuesAbout: section))
    }

    /// Shows no section and no page, and records the place.
    public func clearSelection() {
        go(to: Place(section: nil, page: nil))
    }

    /// Shows a section with no page chosen, and records the place. The one way to change section.
    public func select(section id: WikiSection.ID?) {
        guard let id else { return }
        go(to: Place(section: id, page: nil))
    }

    /// Selects a page of the wiki and records the place. A page that does not exist does nothing.
    public func select(page ref: PageRef) {
        guard store.page(ref) != nil else { return }
        let id = section(of: ref)?.id
        // Picking a page of the restricted issues list keeps the restriction.
        go(to: Place(section: id, page: ref, issuesAbout: id == selectedSection ? issueFilter : nil))
    }

    public func back() {
        guard position > 0 else { return }
        position -= 1
        restore(history[position])
    }

    public func forward() {
        guard position + 1 < history.count else { return }
        position += 1
        restore(history[position])
    }

    private func section(of ref: PageRef) -> WikiSection? {
        metamodel.sections.first { $0.folders.contains(ref.folder) }
    }

    private func go(to place: Place) {
        if position >= 0, history[position] == place { return }
        history = Array(history.prefix(position + 1)) + [place]
        if history.count > Self.longestHistory { history.removeFirst(history.count - Self.longestHistory) }
        position = history.count - 1
        restore(place)
    }

    private func restore(_ place: Place) {
        selectedSection = place.section
        selectedPage = place.page
        issueFilter = place.issuesAbout
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
