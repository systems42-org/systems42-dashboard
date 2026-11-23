import Foundation
import Observation
import Systems42Kit

/// The projections of the open wiki, computed once per revision and per setting of "agreed only", off the main thread.
/// The session owns the model and the model holds the session weakly. A result for an older key is dropped.
@MainActor @Observable public final class ProjectionsModel {
    /// What the data was computed for.
    struct Key: Hashable, Sendable {
        let revision: Int
        let agreedOnly: Bool
    }

    private weak var session: WikiSession?
    /// What the views show. A new computation that gives the same content leaves it as it is, so the views see no change.
    private(set) var data: ProjectionData?
    /// The newest computation, for what needs the snapshot of the current wiki. `data` may be older with the same content.
    private(set) var latest: ProjectionData?
    /// True when a new computation has run longer than `updatingDelay`. Views dim only then.
    private(set) var isUpdating = false
    /// How long a recompute may take before the views say "Updating".
    static let updatingDelay = Duration.milliseconds(400)
    @ObservationIgnored private let updatingDelay: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var running: (key: Key, task: Task<ProjectionData, Never>)?
    /// Makes the data off the main thread. Tests pass their own to hold a computation.
    typealias Build = @Sendable (WikiStore, Metamodel, Bool, Int) async -> ProjectionData
    private let build: Build

    public convenience init(session: WikiSession) {
        self.init(session: session, build: { ProjectionData.build(store: $0, metamodel: $1, agreedOnly: $2, revision: $3) })
    }

    convenience init(session: WikiSession, build: @escaping Build) {
        self.init(session: session, build: build, updatingDelay: Self.updatingDelay)
    }

    init(session: WikiSession, build: @escaping Build, updatingDelay: Duration) {
        self.session = session
        self.build = build
        self.updatingDelay = updatingDelay
    }

    /// The key the data should have now. Nil when the session is gone.
    var currentKey: Key? {
        session.map { Key(revision: $0.revision, agreedOnly: $0.agreedOnly) }
    }

    /// Whether the data on hand is for the current wiki and setting.
    var isCurrent: Bool {
        guard let latest, let key = currentKey else { return false }
        return latest.revision == key.revision && latest.agreedOnly == key.agreedOnly
    }

    /// Computes the projections for the current key, unless they are on hand. Returns when the data is set
    /// or the key has changed meanwhile, in which case the caller asks again.
    func load() async {
        guard let session, let key = currentKey, !isCurrent else { return }
        let task: Task<ProjectionData, Never>
        if let running, running.key == key {
            task = running.task
        } else {
            running?.task.cancel()
            let store = session.store, metamodel = session.metamodel, build = self.build
            task = Task.detached(priority: .userInitiated) {
                await build(store, metamodel, key.agreedOnly, key.revision)
            }
            running = (key, task)
            startTimer()
        }
        let result = await task.value
        guard currentKey == key, !Task.isCancelled else { return }
        latest = result
        if let shown = data, shown.sameContent(as: result) {} else { data = result }
        if running?.key == key { running = nil }
        timer?.cancel()
        timer = nil
        isUpdating = false
    }

    /// Says "updating" only when the computation outlasts the delay. Data to dim must exist.
    private func startTimer() {
        timer?.cancel()
        isUpdating = false
        guard data != nil else { timer = nil; return }
        let delay = updatingDelay
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.isUpdating = true
        }
    }

    /// Opens the page of a card, a row or a node. The session is the only writer of the selection.
    func select(_ ref: PageRef) {
        session?.selectInProjection(ref)
    }

    /// The children and the building blocks of a requirement, computed off the main thread.
    func detail(of ref: PageRef) async -> HierarchyDetail {
        // The data must come from the wiki the store holds, else the two would disagree.
        guard let session, let page = session.store.page(ref), let latest, latest.revision == session.revision else {
            return HierarchyDetail(children: [], buildingBlocks: [])
        }
        let id = page.id, projections = latest.projections
        return await Task.detached(priority: .userInitiated) {
            let found = projections.detail(of: id)
            return HierarchyDetail(children: found.children.map(ProjectionItem.init), buildingBlocks: found.buildingBlocks.map(ProjectionItem.init))
        }.value
    }
}

extension WikiSession {
    /// The projections of this wiki. One per session, so every view of a window shares the computed data.
    public var projections: ProjectionsModel {
        if let model = projectionsModelStore { return model }
        let model = ProjectionsModel(session: self)
        projectionsModelStore = model
        return model
    }
}
