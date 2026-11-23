import Foundation

/// What the requirement projections (hierarchy, story map, goal matrix, backlog) read from the wiki,
/// and the story-map hierarchy of `BuildFRHierarchy`. Port of `internal/project/goals_fr.go`.
///
/// Open debt (CON-006): the type, field, relation and value names below are the Go dashboard's.
/// The metamodel declares the fields in `proj-story-map`, `proj-goal-coverage` and `proj-backlog-ranking`
/// but not the values `agile`, `epic` and the like, nor the url shapes.
enum FR {
    // Content types. Go: types.go TypeFolder, used in goals_fr.go as folder names.
    static let requirementType = "functional-requirement"
    static let goalType = "goal"
    static let blockType = "building-block"

    // Fields of a requirement. Go: goals_fr.go FRNotation, FRLevel, inEnablerLane, frNode.
    static let notationField = "notation"
    static let levelField = "level"
    static let laneField = "lane"
    static let orderField = "order"
    static let priorityField = "priority"
    static let releaseField = "release"
    static let shortTitleField = "short_title"
    static let stereotypeField = "stereotype"

    // Relations by name, their fields come from the metamodel.
    static let parentRelation = "parent"
    static let goalRelation = "goal"
    static let driversRelation = "drivers"

    // Values. Go: goals_fr.go lines 19-24 (`enablerLanes`, `agileLevels`, `ucRefinableLevels`).
    static let agile = "agile"
    static let useCase = "use-case"
    static let epic = "epic", feature = "feature", story = "story"
    static let seaLevel = "sea", fishLevel = "fish"
    static let platformLane = "platform", displayLane = "display"
    static let visionStereotype = "vision"
    /// Go: goals_fr.go `BuildFRHierarchy`, `p.Status() != "deprecated"`.
    static let deprecatedStatus = "deprecated"
    /// The release a page has when it names none. Go: the metamodel says "`unscheduled` = not planned"
    /// (type-functional-requirement.md, field `release`).
    static let unscheduled = "unscheduled"

    /// Priorities in the order the metamodel lists the values of the `priority` field, lower-cased.
    static func priorityRanks(_ model: ProjectionModel) -> [String: Int] {
        let values = model.metamodel.type(named: requirementType)?.fields.first { $0.name == priorityField }?.values ?? []
        return Dictionary(values.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The order of releases in the backlog and the story map: by name with numbers by value
    /// (`v2` before `v10`), `unscheduled` last. `proj-backlog-ranking` does not say more.
    static func releaseLess(_ a: String, _ b: String) -> Bool {
        if (a == unscheduled) != (b == unscheduled) { return b == unscheduled }
        return naturalLess(a, b)
    }

    /// Compares digit runs by value and everything else by bytes.
    static func naturalLess(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
        var i = 0, j = 0
        while i < x.count, j < y.count {
            if isDigit(x[i]), isDigit(y[j]) {
                var ei = i, ej = j
                while ei < x.count, isDigit(x[ei]) { ei += 1 }
                while ej < y.count, isDigit(y[ej]) { ej += 1 }
                let da = x[i..<ei].drop { $0 == 0x30 }, db = y[j..<ej].drop { $0 == 0x30 }
                if da.count != db.count { return da.count < db.count }
                if let diff = zip(da, db).first(where: { $0 != $1 }) { return diff.0 < diff.1 }
                (i, j) = (ei, ej)
            } else {
                if x[i] != y[j] { return x[i] < y[j] }
                i += 1
                j += 1
            }
        }
        return x.count - i < y.count - j
    }

    static func notation(_ page: Page) -> String { page.lowered(notationField) }
    static func level(_ page: Page) -> String { page.lowered(levelField) }
    static func inEnablerLane(_ page: Page) -> Bool {
        [platformLane, displayLane].contains(page.lowered(laneField))
    }

    static func isAgile(_ page: Page) -> Bool { notation(page) == agile }

    /// Ports `frFirstParent`.
    static func firstParent(_ page: Page, model: ProjectionModel) -> String {
        page.names(model.field(ofRelation: parentRelation)).first { !$0.isEmpty } ?? ""
    }

    /// Ports `sortFRPages`: by `order`, then id.
    static func sorted(_ pages: [Page], model: ProjectionModel) -> [Page] {
        pages.enumerated().sorted { a, b in
            let oa = a.element.order(field: orderField), ob = b.element.order(field: orderField)
            if oa != ob { return oa < ob }
            if a.element.id != b.element.id { return Common.less(a.element.id, b.element.id) }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// One node of `BuildFRHierarchy` (Go `frNode` plus the keys the epic and feature rows add).
struct FRRow: Sendable {
    let page: Page
    var features: [FRRow] = []
    /// The stories of a feature.
    var stories: [FRRow] = []
    var directStories: [FRRow] = []
    var featureCount = 0
    var storyCount = 0

    var level: String { FR.level(page) }
}

/// The result of `BuildFRHierarchy`.
struct FRHierarchy: Sendable {
    var epics: [FRRow] = []
    var useCases: [FRRow] = []
    var orphans: [FRRow] = []
    var otherNotations: [FRRow] = []
}

extension FR {
    /// Ports `BuildFRHierarchy`. `frs` are the pages of the requirement type.
    static func hierarchy(_ frs: [Page], model: ProjectionModel) -> FRHierarchy {
        let allPages = frs.filter { $0.status != deprecatedStatus }
        var pages: [Page] = []
        var byStem: [String: Page] = [:]
        var useCases: [String: Page] = [:]
        for page in allPages {
            let notation = notation(page), level = level(page)
            if notation == agile, [epic, feature, story].contains(level) {
                pages.append(page)
                byStem[page.stem] = page
            } else if notation == useCase, [seaLevel, fishLevel].contains(level) {
                useCases[page.stem] = page
            }
        }

        var children: [String: [Page]] = [:]
        for page in pages {
            let parent = firstParent(page, model: model)
            if !parent.isEmpty { children[parent, default: []].append(page) }
        }
        func kids(_ stem: String, _ level: String) -> [Page] {
            sorted((children[stem] ?? []).filter { FR.level($0) == level }, model: model)
        }

        func breakdown(_ root: Page) -> FRRow {
            var row = FRRow(page: root)
            for feature in kids(root.stem, FR.feature) {
                var featureRow = FRRow(page: feature)
                featureRow.stories = kids(feature.stem, FR.story).map { FRRow(page: $0) }
                row.storyCount += featureRow.stories.count
                row.features.append(featureRow)
            }
            row.featureCount = row.features.count
            row.directStories = kids(root.stem, FR.story).map { FRRow(page: $0) }
            row.storyCount += row.directStories.count
            return row
        }

        var result = FRHierarchy()
        result.epics = sorted(pages.filter { level($0) == epic }, model: model).map(breakdown)

        var placed = Set(byStem.keys)
        let useCasePages = allPages.filter { useCases[$0.stem]?.ref == $0.ref }
        for useCase in sorted(useCasePages, model: model) {
            if kids(useCase.stem, feature).isEmpty && kids(useCase.stem, story).isEmpty { continue }
            result.useCases.append(breakdown(useCase))
            placed.insert(useCase.stem)
        }

        for page in pages where [feature, story].contains(level(page)) {
            let parent = firstParent(page, model: model)
            if parent.isEmpty || (byStem[parent] == nil && useCases[parent] == nil) {
                result.orphans.append(FRRow(page: page))
            }
        }
        let others = allPages.filter { !placed.contains($0.stem) }
        result.otherNotations = ProjectionModel.sortedByID(others).map { FRRow(page: $0) }
        return result
    }

    /// Ports `FRHierarchyNode`: the row of a stem in the hierarchy, and its level.
    static func node(_ hierarchy: FRHierarchy, stem: String) -> (row: FRRow, level: String)? {
        func check(_ root: FRRow, isUseCase: Bool) -> (FRRow, String)? {
            if root.page.stem == stem { return (root, isUseCase ? root.level : epic) }
            for feature in root.features {
                if feature.page.stem == stem { return (feature, FR.feature) }
                if let story = feature.stories.first(where: { $0.page.stem == stem }) { return (story, FR.story) }
            }
            if let story = root.directStories.first(where: { $0.page.stem == stem }) { return (story, FR.story) }
            return nil
        }
        for epicRow in hierarchy.epics { if let hit = check(epicRow, isUseCase: false) { return hit } }
        for useCaseRow in hierarchy.useCases { if let hit = check(useCaseRow, isUseCase: true) { return hit } }
        return nil
    }

    /// Ports `FRBuildingBlocks`: the blocks whose `drivers:` names the stem, by id.
    static func buildingBlocks(of stem: String, model: ProjectionModel) -> [Page] {
        let field = model.field(ofRelation: driversRelation)
        return ProjectionModel.sortedByID(model.pages(ofType: blockType)).filter { block in
            block.links(field, existing: { model.byStem[$0] != nil }).contains(stem)
        }
    }
}
