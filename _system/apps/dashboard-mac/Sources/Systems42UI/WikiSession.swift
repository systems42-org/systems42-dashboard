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
                for page in store.pages(in: folder) {
                    found.add(status: page.status.lowercased())
                    issues.formUnion(store.openIssues(for: page.ref).map(\.id))
                }
            }
            found.openIssues = issues.count
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
    /// The section whose issues the issues section lists, set by `showIssues(of:)`.
    public private(set) var issueFilter: WikiSection.ID?

    private let figures: [String: SectionFigures]
    public let orientation: Orientation?
    private var history: [Place] = []
    private var position = -1

    private static let longestHistory = 100

    private struct Place: Equatable {
        let section: WikiSection.ID?
        let page: PageRef?
    }

    init(loaded: LoadedWiki, root: WikiRoot) {
        self.root = root
        config = loaded.config
        store = loaded.store
        metamodel = loaded.metamodel
        figures = loaded.figures
        orientation = loaded.orientation
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
        let shown = agreedOnly ? ordered.filter { $0.status == agreedStatus } : ordered
        return SidebarRow(
            section: section,
            count: shown.reduce(0) { $0 + $1.count },
            byStatus: shown,
            openIssues: all.openIssues,
            agreedShare: all.count == 0 ? 0 : Double(all.agreed) / Double(all.count),
            showsMaturity: lifecycle?.contains(agreedStatus) == true
        )
    }

    /// Selects the section and page a link points at. Other targets and missing pages do nothing.
    public func open(_ target: LinkTarget) {
        guard case .page(let ref) = target, store.page(ref) != nil else { return }
        go(to: Place(section: section(of: ref)?.id, page: ref))
    }

    /// Opens the issues section, filtered to the issues that point at `section`.
    public func showIssues(of section: WikiSection.ID) {
        guard let issues = metamodel.issueSection else { return }
        issueFilter = section
        go(to: Place(section: issues.id, page: nil))
    }

    /// Shows a section with no page chosen, and records the place. The one way to change section.
    public func select(section id: WikiSection.ID?) {
        guard let id else { return }
        go(to: Place(section: id, page: nil))
    }

    /// Selects a page of the wiki and records the place. A page that does not exist does nothing.
    public func select(page ref: PageRef) {
        guard store.page(ref) != nil else { return }
        go(to: Place(section: section(of: ref)?.id, page: ref))
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
    }
}
