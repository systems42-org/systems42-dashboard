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
    private(set) var data: ProjectionData?
    @ObservationIgnored private var running: (key: Key, task: Task<ProjectionData, Never>)?
    /// Makes the data off the main thread. Tests pass their own to hold a computation.
    typealias Build = @Sendable (WikiStore, Metamodel, Bool, Int) async -> ProjectionData
    private let build: Build

    public convenience init(session: WikiSession) {
        self.init(session: session, build: { ProjectionData.build(store: $0, metamodel: $1, agreedOnly: $2, revision: $3) })
    }

    init(session: WikiSession, build: @escaping Build) {
        self.session = session
        self.build = build
    }

    /// The key the data should have now. Nil when the session is gone.
    var currentKey: Key? {
        session.map { Key(revision: $0.revision, agreedOnly: $0.agreedOnly) }
    }

    /// Whether the data on hand is for the current wiki and setting.
    var isCurrent: Bool {
        guard let data, let key = currentKey else { return false }
        return data.revision == key.revision && data.agreedOnly == key.agreedOnly
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
        }
        let result = await task.value
        guard currentKey == key, !Task.isCancelled else { return }
        data = result
        if running?.key == key { running = nil }
    }

    /// Opens the page of a card, a row or a node. The session is the only writer of the selection.
    func select(_ ref: PageRef) {
        session?.selectInProjection(ref)
    }

    /// The children and the building blocks of a requirement, computed off the main thread.
    func detail(of ref: PageRef) async -> HierarchyDetail {
        // The data must come from the wiki the store holds, else the two would disagree.
        guard let session, let page = session.store.page(ref), let data, data.revision == session.revision else {
            return HierarchyDetail(children: [], buildingBlocks: [])
        }
        let id = page.id, projections = data.projections
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
