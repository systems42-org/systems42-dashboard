import Foundation
import Systems42Kit

/// The projections drawn as graph diagrams: which Kit diagram each one shows. A mode is the name of a
/// projection page of the metamodel, so no mode is named after a folder.
///
/// Open debt (CON-006): the metamodel does not say how a projection is drawn or which Kit diagram it is,
/// so this table is code. `Projections.mermaid(_:)` answers to the names on the right.
enum GraphModes {
    static let context = "context-diagram", deployment = "deployment-diagram", entities = "entity-diagram"
    static let buildingBlocks = "bb-tree", goalTree = "goal-tree"
    /// The term network has its own view, with a toggle per layer.
    static let termNetwork = "terminology-graph"

    /// The types whose folder name is the Kit's name of a diagram.
    static let buildingBlockType = "building-block", goalType = "goal"

    /// The projections that are drawn from Mermaid text.
    static let mermaidModes = [context, deployment, entities, buildingBlocks, goalTree]

    /// Every graph projection a section may offer.
    static let all = mermaidModes + [termNetwork]

    /// The name `Projections.mermaid(_:)` knows the diagram of a projection by.
    static func kitName(of mode: String, metamodel: Metamodel) -> String? {
        func folder(_ type: String) -> String? { metamodel.type(named: type)?.folder.split(separator: "/").last.map(String.init) }
        switch mode {
        case context: return "context"
        case deployment: return "deployment"
        case entities: return "data-model"
        case buildingBlocks: return folder(buildingBlockType)
        case goalTree: return folder(goalType)
        default: return nil
        }
    }

    static func diagrams(projections: Projections, metamodel: Metamodel) -> [String: DiagramSource] {
        var found: [String: DiagramSource] = [:]
        let offered = Set(projections.available)
        for mode in mermaidModes where offered.contains(mode) {
            if let name = kitName(of: mode, metamodel: metamodel), let text = projections.mermaid(name) { found[mode] = .mermaid(text) }
        }
        return found
    }

    /// What the reader is told when a graph has nothing to draw.
    static func emptyHint(for mode: String) -> String {
        switch mode {
        case termNetwork: "No domain terms yet, so there is no network to show."
        default: "Nothing to draw for this view yet."
        }
    }
}
