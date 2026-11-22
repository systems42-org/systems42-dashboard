import Foundation

/// The views of a wiki, computed from page fields and never stored: the requirement hierarchy, the story
/// map, the goal coverage matrix, the backlog and the diagrams. A value built from a store and its
/// metamodel, safe to build and use off the main actor. It is a snapshot: build a new one after the wiki changed.
///
/// The Go dashboard computes the same views in `internal/project/` and `internal/web/projections.go`.
/// Each Swift function names the Go function it ports.
public struct Projections: Sendable {
    let model: ProjectionModel

    /// With `agreedOnly` the pages the metamodel's lifecycle marks as not agreed are left out of every
    /// view, see `Metamodel.isHiddenWhenAgreedOnly`.
    public init(store: WikiStore, metamodel: Metamodel, agreedOnly: Bool) {
        model = ProjectionModel(store: store, metamodel: metamodel, agreedOnly: agreedOnly)
    }

    /// The requirements as a tree: epics and use cases at the top, features and stories below.
    public func hierarchy() -> [TreeNode] {
        HierarchyProjection(model: model).roots()
    }

    /// The pages that name the page in `parent:`, and the building blocks that name it in `drivers:`.
    public func detail(of id: String) -> (children: [Page], buildingBlocks: [Page]) {
        HierarchyProjection(model: model).detail(of: id)
    }

    public func storyMap() -> StoryMap {
        StoryMap(backbone: HierarchyProjection(model: model).split().backbone)
    }

    public func goalMatrix() -> GoalMatrix {
        GoalsProjection(model: model).matrix()
    }

    /// The requirements ranked by priority, then release, then `order`, then id.
    public func backlog() -> [Page] {
        BacklogProjection(model: model).ranked()
    }

    /// The Mermaid text of a diagram, as the Go dashboard writes it (without a final newline).
    /// Nil when the wiki has nothing to draw for it.
    ///
    /// - The name of the goal folder: vision and objectives. `story-map`: goals and epics.
    /// - `context`, `data-model` (also `models`), the name of the building block folder (the level 1
    ///   white box), `deployment`.
    /// - `page-<ID>`: the diagram on the page of that id. A requirement shows its breakdown and blocks,
    ///   a building block its white box, a runtime scenario its sequence, a deployment node its subtree
    ///   and a context page the context diagram. `runtime/<ID>` is the sequence of a scenario.
    public func mermaid(_ name: String) -> String? {
        // The golden file names of the goal tree and the level 1 white box are the folder names of
        // the goal and building block types. The folder comes from the metamodel, not from this file.
        if let goals = model.folder(ofType: FR.goalType), name == goals {
            return GoalsProjection(model: model).goalTreeDiagram()
        }
        if let blocks = model.folder(ofType: Arch.blockType), name == blocks {
            return BuildingBlocksProjection(model: model).whitebox(of: "")
        }
        switch name {
        case Name.storyMap: return GoalsProjection(model: model).goalEpicDiagram()
        case Name.context: return ContextProjection(model: model).diagram()
        case Name.dataModel, Name.models: return DataModelProjection(model: model).diagram()
        case Name.deployment: return DeploymentProjection(model: model).diagram()
        default:
            if name.hasPrefix(Name.runtimePrefix) {
                guard let page = page(id: String(name.dropFirst(Name.runtimePrefix.count))),
                      page.ref.folder == model.folder(ofType: Arch.scenarioType) else { return nil }
                return RuntimeProjection(model: model).sequenceDiagram(of: page)
            }
            if name.hasPrefix(Name.pagePrefix) { return pageDiagram(String(name.dropFirst(Name.pagePrefix.count))) }
            return nil
        }
    }

    /// Cytoscape data: `term-network` (also `terms`) with all edges, `term-network-related` and
    /// `term-network-structured` with one kind of edge, and `metamodel-graph` (also `metamodel`).
    public func graph(_ name: String) -> Graph? {
        switch name {
        case Name.termNetwork, Name.terms: return TermNetworkProjection(model: model).graph(edges: .all)
        case Name.termNetworkRelated: return TermNetworkProjection(model: model).graph(edges: .related)
        case Name.termNetworkStructured: return TermNetworkProjection(model: model).graph(edges: .structured)
        case Name.metamodelGraph, Name.metamodel: return MetamodelGraphProjection(metamodel: model.metamodel).graph()
        default: return nil
        }
    }

    /// The term network with layers on. `layers` are type names such as `stakeholder`: the terms and
    /// the neighbours of those types are shown.
    public func termNetwork(layers: Set<String>) -> Graph {
        TermNetworkProjection(model: model).layered(layers)
    }

    /// A term and its neighbours of the kinds the page of a term shows. Empty when the id is no term.
    public func termNeighbourhood(of id: String) -> Graph {
        guard let page = page(id: id) else { return Graph() }
        return TermNetworkProjection(model: model).ego(of: page.stem)
    }

    /// The page with this id, else the page with this stem.
    private func page(id: String) -> Page? {
        model.all.first { $0.id == id } ?? model.byStem[id]
    }

    private func pageDiagram(_ id: String) -> String? {
        guard let page = page(id: id) else { return nil }
        let folder = page.ref.folder
        switch folder {
        case model.folder(ofType: FR.requirementType): return HierarchyProjection(model: model).subtreeDiagram(of: page)
        case model.folder(ofType: Arch.blockType): return BuildingBlocksProjection(model: model).whitebox(of: page.stem)
        case model.folder(ofType: Arch.scenarioType): return RuntimeProjection(model: model).sequenceDiagram(of: page)
        case model.folder(ofType: Arch.nodeType): return DeploymentProjection(model: model).diagram(root: page.stem)
        case model.folder(ofType: Name.contextType): return ContextProjection(model: model).diagram()
        default: return nil
        }
    }

    /// The names `mermaid` and `graph` answer to. They are the file names of the golden data
    /// (`Tests/Golden/<fixture>/diagrams/`), and the type that has a diagram of its own on its page.
    enum Name {
        static let storyMap = "story-map", context = "context", dataModel = "data-model"
        static let models = "models", deployment = "deployment"
        static let termNetwork = "term-network", terms = "terms", termNetworkRelated = "term-network-related"
        static let termNetworkStructured = "term-network-structured"
        static let metamodelGraph = "metamodel-graph", metamodel = "metamodel"
        static let pagePrefix = "page-", runtimePrefix = "runtime/"
        /// Go: web/detail.go `case "context"`. The context page carries the context diagram.
        static let contextType = "context"
    }
}
