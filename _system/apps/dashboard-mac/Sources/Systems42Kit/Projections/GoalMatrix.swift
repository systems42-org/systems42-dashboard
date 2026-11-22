import Foundation

/// The goal coverage matrix: objectives as rows, epics and use cases as columns (FR-036).
/// Port of `LoadGoals` and `GoalMatrix` of `internal/project/goals_fr.go`.
public struct GoalMatrix: Sendable {
    /// The objectives, by id. The vision is no row.
    public let goals: [Page]
    /// Epics that are no enablers, then use cases, then the enabler epics.
    public let columns: [Page]
    /// Epics in lane platform or display that name no goal.
    public let enablers: [Page]
    /// Goals no requirement serves.
    public let gaps: Set<String>
    /// Goals no agreed requirement serves, whether or not "agreed only" is on.
    public let acceptedGaps: Set<String>
    /// Epics and features of the agile notation that name no goal and are no enablers.
    /// The Go dashboard flags the epics as against the rule and the features the same way.
    public let untraced: Set<String>

    let coverage: [String: [Page]]
    let marks: [String: Set<String>]

    /// Whether the column serves the goal. Both are page ids.
    public func marked(goal: String, column: String) -> Bool {
        marks[goal]?.contains(column) == true
    }

    /// Every requirement that serves the goal, features and stories and other notations included.
    public func servedBy(goal: String) -> [Page] {
        coverage[goal] ?? []
    }

    /// The requirements the row of the goal names instead of a mark: when no column serves the goal,
    /// its features, then its stories, then other requirements. Empty when a column serves it.
    /// With `acceptedOnly` only accepted requirements count.
    public func servedWithoutColumn(goal: String, acceptedOnly: Bool = false) -> [Page] {
        let serving = (coverage[goal] ?? []).filter { !acceptedOnly || $0.status == GoalsProjection.acceptedStatus }
        let columnIDs = Set(columns.map(\.id))
        if serving.contains(where: { columnIDs.contains($0.id) }) { return [] }
        var out: [Page] = []
        for level in [FR.feature, FR.story] {
            out += serving.filter { FR.notation($0) == FR.agile && FR.level($0) == level }
        }
        out += serving.filter { ![FR.agile, FR.useCase].contains(FR.notation($0)) }
        return out
    }
}

/// What `LoadGoals` returns.
struct GoalsData {
    var vision: Page?
    var objectives: [Page] = []
    var coverage: [String: [Page]] = [:]
    var enablers: [Page] = []
    var untraced: [Page] = []
    var requirements: [Page] = []
    var useCases: [Page] = []
}

struct GoalsProjection {
    let model: ProjectionModel

    /// Go: goals_fr.go `GoalMatrix`, `p.Status() == "accepted"` for the accepted view.
    static let acceptedStatus = "accepted"

    func shortTitle(_ page: Page) -> String {
        let short = page.trimmed(FR.shortTitleField)
        return short.isEmpty ? Common.trim(page.title) : short
    }

    /// Ports `wiki.VisionPage`: the goal with the lowest id and stereotype vision.
    func vision(of goals: [Page]) -> Page? {
        goals.first { $0.lowered(FR.stereotypeField) == FR.visionStereotype }
    }

    /// Ports `LoadGoals`.
    func load() -> GoalsData {
        let goals = ProjectionModel.sortedByID(model.pages(ofType: FR.goalType))
        var data = GoalsData()
        let vision = vision(of: goals)
        data.vision = vision
        var objectiveByStem: [String: Page] = [:]
        for goal in goals where goal.ref != vision?.ref {
            data.objectives.append(goal)
            objectiveByStem[goal.stem] = goal
            data.coverage[goal.id] = []
        }

        let all = ProjectionModel.sortedByID(model.pages(ofType: FR.requirementType))
        var useCaseByStem: [String: Page] = [:]
        var nonUseCases: [Page] = []
        for page in all {
            if FR.notation(page) == FR.useCase {
                data.useCases.append(page)
                if [FR.seaLevel, FR.fishLevel].contains(FR.level(page)) { useCaseByStem[page.stem] = page }
            } else {
                nonUseCases.append(page)
            }
        }
        data.requirements = nonUseCases

        let goalField = model.field(ofRelation: FR.goalRelation)
        func served(_ page: Page) -> [String] {
            page.links(goalField, existing: { model.byStem[$0] != nil }).compactMap { objectiveByStem[$0]?.id }
        }

        for requirement in nonUseCases {
            var goalIDs = served(requirement)
            let level = FR.level(requirement)
            if goalIDs.isEmpty, FR.notation(requirement) == FR.agile, level == FR.feature || level == FR.story {
                let first = FR.firstParent(requirement, model: model)
                if !first.isEmpty, let useCase = useCaseByStem[first] { goalIDs = served(useCase) }
            }
            if goalIDs.isEmpty && FR.inEnablerLane(requirement) {
                data.enablers.append(requirement)
            } else if FR.notation(requirement) == FR.agile, level == FR.epic || level == FR.feature,
                      goalIDs.isEmpty, !FR.inEnablerLane(requirement) {
                data.untraced.append(requirement)
            }
            for id in goalIDs { data.coverage[id, default: []].append(requirement) }
        }
        for useCase in data.useCases {
            for id in served(useCase) where !(data.coverage[id] ?? []).contains(where: { $0.ref == useCase.ref }) {
                data.coverage[id, default: []].append(useCase)
            }
        }
        return data
    }

    func matrix() -> GoalMatrix {
        let data = load()
        let enablerIDs = Set(data.enablers.map(\.id))
        let epics = data.requirements.filter { FR.notation($0) == FR.agile && FR.level($0) == FR.epic }
        let columns = epics.filter { !enablerIDs.contains($0.id) } + data.useCases + epics.filter { enablerIDs.contains($0.id) }
        let columnIDs = Set(columns.map(\.id))

        var gaps = Set<String>(), acceptedGaps = Set<String>()
        var marks: [String: Set<String>] = [:]
        for objective in data.objectives {
            let serving = data.coverage[objective.id] ?? []
            if serving.isEmpty { gaps.insert(objective.id) }
            if !serving.contains(where: { $0.status == GoalsProjection.acceptedStatus }) { acceptedGaps.insert(objective.id) }
            marks[objective.id] = Set(serving.map(\.id).filter(columnIDs.contains))
        }
        return GoalMatrix(
            goals: data.objectives, columns: columns, enablers: data.enablers,
            gaps: gaps, acceptedGaps: acceptedGaps, untraced: Set(data.untraced.map(\.id)),
            coverage: data.coverage, marks: marks
        )
    }

    /// Ports `MermaidGoalTree`: vision, then its objectives. Nil without a vision or objectives.
    func goalTreeDiagram() -> String? {
        let data = load()
        guard let vision = data.vision, !data.objectives.isEmpty else { return nil }
        let root = Common.cleanLabel(model.systemName, dropParenthetical: false)
        var lines = [
            "graph TD",
            "  V[\"Vision \(root)\"]:::vision",
            "  click V \"\(FR.goalURL)\(vision.id)\"",
        ]
        for objective in data.objectives {
            let nid = Common.diagramNodeID(objective.id)
            let label = Common.cleanLabel(shortTitle(objective), dropParenthetical: true)
            lines.append("  V --> \(nid)[\"\(objective.id)<br/>\(label)\"]:::goal")
            lines.append("  click \(nid) \"\(FR.goalURL)\(objective.id)\"")
        }
        lines += [
            "  classDef vision fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
            "  classDef goal fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        ]
        return lines.joined(separator: "\n")
    }
}
