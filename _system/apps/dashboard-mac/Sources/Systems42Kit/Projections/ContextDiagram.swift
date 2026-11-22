import Foundation

/// The system context diagram, projected from the flows of external interfaces and the `provides` and
/// `receives` of stakeholders (DR-013, DR-014, DR-026). Port of `BuildContextDiagram` in
/// `internal/project/context.go`.
///
/// Open debt (CON-006): `proj-context-diagram` declares the types and fields it reads. The tier names,
/// the flow keys and direction words, the node classes and the "Person" label are fixed here.
struct ContextProjection {
    let model: ProjectionModel

    // Content types. Go: web/detail.go, the call of `BuildContextDiagram` with the interface and stakeholder folders.
    static let interfaceType = "external-interface"
    static let stakeholderType = "stakeholder"

    // Fields. Go: context.go `eifNodeLabel`, `eifFlows`, `BuildContextDiagram`.
    static let shortTitleField = "short_title", partnerField = "partner", tierField = "tier", flowsField = "flows"
    static let providesField = "provides", receivesField = "receives", roleField = "context_role", natureField = "nature"
    static let labelKey = "label", dataKey = "data", directionKey = "direction"

    // Values. Go: context.go lines 10-30, `eifFlows`, `BuildContextDiagram`.
    static let deprecatedStatus = "deprecated"
    static let inbound = "inbound", outbound = "outbound", bidirectional = "bidirectional"
    static let noRole = "none"
    static let organization = "organization"
    /// The bands of the diagram in drawing order: key, label, side. Go: `tierBands`.
    static let tierBands: [(key: String, label: String, side: String)] = [
        ("supply", "Supply", "left"), ("support", "Support", "left"),
        ("demand", "Demand", "right"), ("core-operations", "Core operations", "right"),
    ]
    static let core = "CORE"
    static let personPrefix = "Person · "
    /// The projection page this reads.
    static let projection = "context-diagram"
    static let declaration = ProjectionDeclaration(projection, [
        (interfaceType, [shortTitleField, partnerField, tierField, flowsField]),
        (stakeholderType, [providesField, receivesField, roleField, natureField]),
    ])
    /// The side a band or group is ranked on when nothing says more, and the node classes. Go: `tierSide`, `BuildContextDiagram`.
    static let leftSide = "left", systemClass = "system", actorClass = "actor"
    static let classes = [
        "  classDef core fill:#2f6fb3,stroke:#7fc0ff,stroke-width:2px,color:#ffffff,font-weight:bold;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef actor fill:#f3f6fb,stroke:#aeb8c9,color:#15202e;",
    ]

    private typealias Flow = [String: String]

    private struct Node {
        let nid: String
        let label: String
        let cls: String
    }

    /// Ports `tierSide`.
    private func side(of tier: String) -> String {
        Self.tierBands.first { $0.key == tier }?.side ?? Self.leftSide
    }

    /// Ports `eifNodeLabel`.
    private func nodeLabel(_ page: Page) -> String {
        let short = page.text(Self.shortTitleField)
        if !short.isEmpty { return Common.cleanLabel(short, dropParenthetical: true) }
        if !page.title.isEmpty { return Common.cleanLabel(page.title, dropParenthetical: true) }
        return Common.cleanLabel(page.text(Self.partnerField), dropParenthetical: true)
    }

    /// Ports `flowEdgeLabel`.
    private func edgeLabel(_ flows: [Flow]) -> String {
        var seen: [String] = []
        for flow in flows {
            var label = Common.cleanLabel(flow[Self.labelKey] ?? "", dropParenthetical: true)
            if label.isEmpty {
                label = Common.cleanLabel(flow[Self.dataKey] ?? "", dropParenthetical: true)
                if Common.runeCount(label) > 24 {
                    let cut = Common.firstRunes(label, 23)
                    label = cut.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r")) + "…"
                }
            }
            if !label.isEmpty && !seen.contains(label) { seen.append(label) }
        }
        return seen.joined(separator: " · ")
    }

    /// Ports `eifFlows`: the inbound, the outbound and all flows in order.
    private func flows(of page: Page) -> (ins: [Flow], outs: [Flow], ordered: [Flow]) {
        var ins: [Flow] = [], outs: [Flow] = [], ordered: [Flow] = []
        for case .entry(let flow) in page.entries(Self.flowsField) {
            ordered.append(flow)
            let direction = (flow[Self.directionKey] ?? "").lowercased()
            if direction == Self.inbound || direction == Self.bidirectional { ins.append(flow) }
            if direction == Self.outbound || direction == Self.bidirectional { outs.append(flow) }
        }
        return (ins, outs, ordered)
    }

    /// The diagram, nil when no interface or stakeholder gives an edge.
    func diagram() -> String? {
        let center = Common.cleanLabel(model.systemName, dropParenthetical: false)
        var ids = NodeIDs(reserved: [Self.core] + Self.tierBands.map { Common.diagramNodeID($0.key) })
        var bands: [String: [Node]] = [:]
        var loose: [Node] = []
        var edges: [String] = []

        func addEdge(_ nid: String, ins: [Flow], outs: [Flow], side: String, ordered: [Flow]?) {
            let label: String, source: String, arrow: String, target: String
            if !ins.isEmpty && !outs.isEmpty {
                label = edgeLabel(ordered ?? ins + outs)
                (source, arrow, target) = side == Self.leftSide ? (nid, "<-->", Self.core) : (Self.core, "<-->", nid)
            } else if !ins.isEmpty {
                (label, source, arrow, target) = (edgeLabel(ins), nid, "-->", Self.core)
            } else if !outs.isEmpty {
                (label, source, arrow, target) = (edgeLabel(outs), Self.core, "-->", nid)
            } else {
                return
            }
            edges.append(label.isEmpty ? "  \(source) \(arrow) \(target)" : "  \(source) \(arrow)|\"\(label)\"| \(target)")
        }

        for page in model.pages(ofType: Self.interfaceType) where page.status != Self.deprecatedStatus {
            let (ins, outs, ordered) = flows(of: page)
            if ins.isEmpty && outs.isEmpty { continue }
            let nid = ids.id(of: page)
            let tier = page.lowered(Self.tierField)
            let node = Node(nid: nid, label: nodeLabel(page), cls: Self.systemClass)
            if Self.tierBands.contains(where: { $0.key == tier }) { bands[tier, default: []].append(node) } else { loose.append(node) }
            addEdge(nid, ins: ins, outs: outs, side: side(of: tier), ordered: ordered)
        }

        struct Group {
            let label: String
            var provides: [String] = []
            var receives: [String] = []
            var cls = ContextProjection.actorClass
        }
        var groups: [Group] = []
        var groupIndex: [String: Int] = [:]
        func union(_ target: inout [String], _ items: [String]) {
            for item in items where !target.contains(item) { target.append(item) }
        }

        for page in model.pages(ofType: Self.stakeholderType) {
            let provides = page.textList(Self.providesField), receives = page.textList(Self.receivesField)
            if provides.isEmpty && receives.isEmpty { continue }
            let role = page.text(Self.roleField)
            if case .text? = page.fields[Self.roleField], role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.noRole { continue }
            var label = Common.cleanLabel(page.title, dropParenthetical: true)
            if !role.isEmpty { label = Common.cleanLabel(role, dropParenthetical: true) }
            let isOrganization = page.lowered(Self.natureField) == Self.organization
            let index: Int
            if let known = groupIndex[label] {
                index = known
            } else {
                index = groups.count
                groupIndex[label] = index
                groups.append(Group(label: label))
            }
            if isOrganization { groups[index].cls = Self.systemClass }
            union(&groups[index].provides, provides)
            union(&groups[index].receives, receives)
        }
        for group in groups {
            let nid = ids.id("role:" + group.label, base: Common.diagramNodeID(group.label))
            loose.append(Node(nid: nid, label: group.label, cls: group.cls))
            addEdge(nid, ins: group.provides.map { [Self.dataKey: $0] }, outs: group.receives.map { [Self.dataKey: $0] },
                    side: Self.leftSide, ordered: nil)
        }
        if edges.isEmpty { return nil }

        func nodeLine(_ node: Node) -> String {
            node.cls == Self.actorClass
                ? "  \(node.nid)([\"\(Self.personPrefix)\(node.label)\"]):::actor"
                : "  \(node.nid)[\"\(node.label)\"]:::\(node.cls)"
        }
        var lines = ["flowchart LR"]
        for band in Self.tierBands {
            guard let nodes = bands[band.key], !nodes.isEmpty else { continue }
            lines.append("  subgraph \(Common.diagramNodeID(band.key))[\"\(band.label)\"]")
            lines.append("    direction TB")
            for node in nodes { lines.append("  " + nodeLine(node)) }
            lines.append("  end")
        }
        lines.append("  \(Self.core)[\"\(Common.cleanLabel(center, dropParenthetical: true))\"]:::core")
        for node in loose { lines.append(nodeLine(node)) }
        lines += edges
        lines += Self.classes
        return lines.joined(separator: "\n")
    }
}
