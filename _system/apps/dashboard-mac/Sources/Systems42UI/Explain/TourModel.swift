import Foundation
import Observation
import Systems42Kit

/// The guided tour of one wiki (FR-012). It walks the steps of `TourSteps` that the wiki can show:
/// a step is left out when the metamodel lacks its type or the wiki has no page of it.
/// The model only asks the session to select (the session stays the one writer of the selection).
@MainActor @Observable public final class TourModel {
    /// A step with what the wiki offers for it.
    public struct Stop: Identifiable, Equatable, Sendable {
        public let step: TourStep
        /// The section that holds the step's type, nil for a step with no type.
        public let section: Section.ID?
        /// The page the step shows, nil for a step with no type.
        public let page: PageRef?
        /// The step's projection, only when the metamodel has it.
        public let projection: String?
        public var id: String { step.id }
    }

    public private(set) var isActive = false
    /// The position of the current step in `steps`.
    public var current = 0

    /// Weak: the session owns this model, so a strong reference would be a cycle. A gone session gives no steps.
    private weak var session: WikiSession?
    private var before: (section: Section.ID?, page: PageRef?)?
    /// The step the reader is on, to find it again after a reload.
    private var currentID: String?
    private var followedRevision = -1
    @ObservationIgnored private var cache: (revision: Int, stops: [Stop])?

    public init(session: WikiSession) {
        self.session = session
    }

    /// The steps this wiki can show, in tour order.
    public var steps: [TourStep] { stops.map(\.step) }

    public var stops: [Stop] {
        guard let session else { return [] }
        let revision = session.revision
        if let cache, cache.revision == revision { return cache.stops }
        let stops = Self.resolve(TourSteps.all, in: session)
        cache = (revision, stops)
        return stops
    }

    public var currentStop: Stop? {
        let list = stops
        return list.indices.contains(current) ? list[current] : nil
    }

    /// The revision of the loaded wiki. A view watches it to call `followWiki()`.
    public var revision: Int { session?.revision ?? 0 }

    /// Whether the window still shows the current step. False after the reader left the path.
    public var isOnStep: Bool {
        guard let session, let stop = currentStop else { return false }
        if let page = stop.page { return session.selectedPage == page }
        if let section = stop.section { return session.selectedSection == section }
        return true
    }

    // MARK: Moving

    /// Starts at the first step and remembers the selection. Starting again restarts at the first step.
    public func start() {
        guard let session else { return }
        followWiki()
        guard !stops.isEmpty else { return }
        if !isActive { before = (session.selectedSection, session.selectedPage) }
        isActive = true
        current = 0
        currentID = currentStop?.id
        show()
    }

    /// The next step. After the last step the tour stops.
    public func next() {
        guard isActive else { return }
        followWiki()
        guard isActive else { return }
        if current + 1 >= stops.count { stop(); return }
        current += 1
        currentID = currentStop?.id
        show()
    }

    /// The previous step. At the first step nothing changes.
    public func previous() {
        guard isActive else { return }
        followWiki()
        guard isActive, current > 0 else { return }
        current -= 1
        currentID = currentStop?.id
        show()
    }

    /// Ends the tour and goes back to where the reader was. A page that is gone gives its section,
    /// a section that is gone gives no selection.
    public func stop() {
        guard isActive else { return }
        isActive = false
        guard let session, let before else { return }
        self.before = nil
        if let page = before.page, session.store.page(page) != nil {
            session.select(page: page)
        } else if let section = before.section, session.metamodel.sections.contains(where: { $0.id == section }) {
            session.select(section: section)
        } else {
            session.clearSelection()
        }
    }

    /// Shows the current step again, after the reader looked around.
    public func returnToStep() {
        guard isActive else { return }
        followWiki()
        show()
    }

    /// Brings the steps in line with a reloaded wiki. The current step stays when it still exists,
    /// otherwise the position is clamped. The selection is left alone. With no step left the tour stops.
    public func followWiki() {
        guard let session, session.revision != followedRevision else { return }
        followedRevision = session.revision
        guard isActive else { return }
        let list = stops
        if list.isEmpty { stop(); return }
        if let id = currentID, let index = list.firstIndex(where: { $0.id == id }) {
            current = index
        } else {
            current = min(max(current, 0), list.count - 1)
        }
        currentID = list[current].id
    }

    private func show() {
        guard let session, let stop = currentStop else { return }
        if let page = stop.page {
            session.select(page: page)
        } else if let section = stop.section {
            session.select(section: section)
        }
    }

    // MARK: Resolving

    private static func resolve(_ steps: [TourStep], in session: WikiSession) -> [Stop] {
        let metamodel = session.metamodel
        let visionTitle = session.orientation?.title
        var stops: [Stop] = []
        for step in steps {
            guard let typeName = step.showsType else {
                stops.append(Stop(step: step, section: nil, page: nil, projection: nil))
                continue
            }
            guard let type = metamodel.type(named: typeName),
                  let folder = type.folder.split(separator: "/").last.map(String.init),
                  let section = metamodel.sections.first(where: { $0.types.contains(typeName) }) else { continue }
            let pages = session.store.pages(in: folder)
            // The vision page leads where the step's type holds it.
            guard let page = pages.first(where: { $0.title == visionTitle }) ?? pages.first else { continue }
            let projection = step.showsProjection.flatMap { name in
                metamodel.projections.contains { $0.name == name } ? name : nil
            }
            stops.append(Stop(step: step, section: section.id, page: page.ref, projection: projection))
        }
        return stops
    }
}

extension WikiSession {
    /// The tour of this wiki. One per session, so the window and the Help menu share it.
    public var tour: TourModel {
        if let model = tourModelStore { return model }
        let model = TourModel(session: self)
        tourModelStore = model
        return model
    }
}
