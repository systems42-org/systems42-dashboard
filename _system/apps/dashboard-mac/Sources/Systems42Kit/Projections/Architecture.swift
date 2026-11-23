import Foundation

/// What the architecture projections (building blocks, deployment, runtime) read, and what they share:
/// lifecycle marks and the level tree. Port of `internal/project/arch.go`.
///
/// Open debt (CON-006): the metamodel declares the types and fields in `proj-bb-tree`, `proj-whitebox`,
/// `proj-deployment-diagram` and `proj-sequence-diagram`. It does not declare the state values, the keys
/// of a step or a connection, or the style strings.
enum Arch {
    // Content types. Go: wiki/page.go TypeFolder, arch.go resolveEndpoint.
    static let blockType = "building-block"
    static let nodeType = "deployment-node"
    static let scenarioType = "runtime-scenario"
    static let interfaceType = "external-interface"
    static let stakeholderType = "stakeholder"

    // Relations by name, their fields come from the metamodel.
    static let parentRelation = "parent"
    static let usesRelation = "uses"
    static let hostsRelation = "hosts"
    static let connectsRelation = "connects"
    static let supersededByRelation = "superseded-by"
    static let stepsRelation = "steps"

    // Fields. Go: wiki/page.go `PageState`, arch.go `BuildDeploymentDiagram`.
    static let stateField = "state"
    static let technologyField = "technology"
    // Keys of a step and of a connection. Go: arch.go `StepsOf`, `BuildDeploymentDiagram`.
    static let fromKey = "from", toKey = "to", messageKey = "message", noteKey = "note", protocolKey = "protocol"

    // Values. Go: wiki/page.go `validArchStates`, `PageState`, and `Lifecycle` in common.go.
    static let validStates: Set<String> = ["outdated", "current", "planned", "target"]
    static let defaultState = "target"
    static let outdated = "outdated", planned = "planned", target = "target"
    static let deprecatedStatus = "deprecated"

    // Style strings and fixed labels. Go: arch.go lines 12-14 and the `Sprintf` calls.
    static let dashed = "stroke-dasharray:5 4"
    static let greyed = "fill:#eceef2,stroke:#9aa3b2,color:#6b7280"
    static let replacedBy = "replaced by"
    static let beingReplaced = " · being replaced"

    /// The deepest level a tree is built to. Blocks and nodes nest a handful of levels. A chain
    /// deeper than this is cut: the pages below it become roots of their own, none is lost.
    static let deepest = 64
}

/// Ports `wiki.PageState`.
func pageState(_ page: Page) -> String {
    let state = page.lowered(Arch.stateField)
    return Arch.validStates.contains(state) ? state : Arch.defaultState
}

/// Ports `Lifecycle`: "outdated" for deprecated pages, else the page state.
func lifecycle(_ page: Page) -> String {
    page.status == Arch.deprecatedStatus ? Arch.outdated : pageState(page)
}

func isFutureLifecycle(_ lifecycle: String) -> Bool {
    lifecycle == Arch.planned || lifecycle == Arch.target
}

/// Ports `isMixedLifecycle`.
func isMixedLifecycle(_ pages: [Page]) -> Bool {
    var future = false, other = false
    for page in pages {
        if isFutureLifecycle(lifecycle(page)) { future = true } else { other = true }
    }
    return future && other
}

/// One page in a level tree.
struct LevelNode {
    let page: Page
    var children: [LevelNode]
}

extension ProjectionModel {
    /// Ports `levelTree`: the pages of one folder nested by their first `parent:` that is in the folder.
    /// A page with no such parent is a root. A cycle is cut where it closes, and the pages it leaves
    /// out become roots.
    func levelTree(_ folderPages: [Page]) -> [LevelNode] {
        var pages: [String: Page] = [:]
        for page in folderPages { pages[page.stem] = page }
        let field = self.field(ofRelation: Arch.parentRelation)
        var children: [String: [String]] = [:]
        for page in folderPages {
            let parent = page.links(field, existing: { byStem[$0] != nil }).first { pages[$0] != nil } ?? ""
            children[parent, default: []].append(page.stem)
        }
        func sortedByID(_ stems: [String]) -> [String] {
            stems.enumerated().sorted { a, b in
                let ia = pages[a.element]?.id ?? "", ib = pages[b.element]?.id ?? ""
                return ia == ib ? a.offset < b.offset : Common.less(ia, ib)
            }.map(\.element)
        }

        var seen = Set<String>()
        func build(_ stem: String, depth: Int) -> LevelNode {
            seen.insert(stem)
            var kids: [LevelNode] = []
            if depth < Arch.deepest {
                for child in sortedByID((children[stem] ?? []).filter { !seen.contains($0) }) where !seen.contains(child) {
                    kids.append(build(child, depth: depth + 1))
                }
            }
            return LevelNode(page: pages[stem]!, children: kids)
        }

        var roots: [LevelNode] = []
        for stem in sortedByID(children[""] ?? []) where !seen.contains(stem) { roots.append(build(stem, depth: 0)) }
        for stem in sortedByID(folderPages.map(\.stem).filter { !seen.contains($0) }) where !seen.contains(stem) {
            roots.append(build(stem, depth: 0))
        }
        return roots.enumerated().sorted { a, b in
            a.element.page.id == b.element.page.id ? a.offset < b.offset : Common.less(a.element.page.id, b.element.page.id)
        }.map(\.element)
    }
}

/// Ports `treeFind`.
func treeFind(_ nodes: [LevelNode], stem: String) -> LevelNode? {
    var stack = Array(nodes.reversed())
    while let node = stack.popLast() {
        if node.page.stem == stem { return node }
        stack.append(contentsOf: node.children.reversed())
    }
    return nil
}

/// A page with the key and node id it carries in a diagram, for `lifecycleLines`.
struct MarkedEntry {
    let key: String
    let nid: String
    let page: Page
}

extension ProjectionModel {
    /// The stems a field names, `wiki.LinksOf(page, field, byStem)`.
    func linkedStems(_ page: Page, relation: String) -> [String] {
        page.links(field(ofRelation: relation), existing: { byStem[$0] != nil })
    }

    /// Ports `lifecycleLines`.
    func lifecycleLines(_ entries: [MarkedEntry]) -> [String] {
        let mixed = isMixedLifecycle(entries.map(\.page))
        var nidByKey: [String: String] = [:]
        for entry in entries { nidByKey[entry.key] = entry.nid }
        var lines: [String] = []
        for entry in entries {
            let state = lifecycle(entry.page)
            if state == Arch.outdated {
                lines.append("  style \(entry.nid) \(Arch.greyed)")
            } else if isFutureLifecycle(state) && mixed {
                lines.append("  style \(entry.nid) \(Arch.dashed)")
            }
            for target in linkedStems(entry.page, relation: Arch.supersededByRelation) {
                if let targetID = nidByKey[target] {
                    lines.append("  \(entry.nid) -. \"\(Arch.replacedBy)\" .-> \(targetID)")
                }
            }
        }
        return lines
    }

    /// Ports `lifecycleSuffix`.
    func lifecycleSuffix(_ page: Page, mixed: Bool) -> String {
        let state = lifecycle(page)
        if state == Arch.outdated || (isFutureLifecycle(state) && mixed) { return " · " + state }
        if !linkedStems(page, relation: Arch.supersededByRelation).isEmpty { return Arch.beingReplaced }
        return ""
    }
}
