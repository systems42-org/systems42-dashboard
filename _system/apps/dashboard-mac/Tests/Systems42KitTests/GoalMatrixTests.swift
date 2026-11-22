import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

/// The wiki of `tests/test_goal_matrix.py`: goals and requirements in the shapes the matrix has to tell apart.
private func goalWiki() throws -> TempWiki {
    let wiki = try TempWiki()
    func goal(_ stem: String, _ title: String, _ status: String, _ stereotype: String) throws {
        try wiki.page("goals", stem, title, status, [("stereotype", stereotype)])
    }
    try goal("GOAL-001-vision", "The vision", "accepted", "vision")
    try goal("GOAL-002-served", "Served goal", "accepted", "objective")
    try goal("GOAL-003-unserved", "Unserved goal", "accepted", "objective")
    try goal("GOAL-004-draft", "Draft goal", "draft", "objective")
    try goal("GOAL-005-features-only", "Served by a feature only", "accepted", "objective")
    try goal("GOAL-006-draft-epic-agreed-feature", "Draft epic, agreed feature", "accepted", "objective")
    try goal("GOAL-007-ears-only", "Served by an EARS requirement only", "accepted", "objective")

    func fr(_ stem: String, _ title: String, _ status: String, notation: String = "agile", level: String,
            lane: String? = nil, parent: String = "[]", goal: String) throws {
        var fields = [("notation", notation), ("level", level)]
        if let lane { fields.append(("lane", lane)) }
        fields += [("parent", parent), ("goal", goal)]
        try wiki.page("functional-requirements", stem, title, status, fields)
    }
    try fr("FR-001-served-epic", "Served epic", "accepted", level: "epic", lane: "backbone", goal: "[\"[[GOAL-002-served]]\"]")
    try fr("FR-002-untraced-epic", "Untraced epic", "draft", level: "epic", lane: "backbone", goal: "[]")
    try fr("FR-003-platform-epic", "Platform epic", "accepted", level: "epic", lane: "platform", goal: "[]")
    try fr("FR-004-feature", "A feature", "accepted", level: "feature", lane: "backbone",
           parent: "[\"[[FR-001-served-epic]]\"]", goal: "[\"[[GOAL-002-served]]\"]")
    try fr("FR-005-display-epic", "Display epic", "draft", level: "epic", lane: "display", goal: "[]")
    try fr("FR-006-draft-epic", "Draft epic", "draft", level: "epic", lane: "backbone", goal: "[\"[[GOAL-002-served]]\"]")
    // lane platform, but it names a goal: no enabler
    try fr("FR-007-platform-with-goal", "Platform epic with a goal", "draft", level: "epic", lane: "platform", goal: "[\"[[GOAL-004-draft]]\"]")
    // the only requirement serving GOAL-005: a feature, no matrix column
    try fr("FR-008-feature-only", "Feature for goal five", "draft", level: "feature", lane: "backbone",
           parent: "[\"[[FR-001-served-epic]]\"]", goal: "[\"[[GOAL-005-features-only]]\"]")
    // goal values that name no objective, and two odd spellings that do
    try fr("FR-009-names-the-vision", "Names the vision", "draft", level: "epic", lane: "backbone", goal: "[\"[[GOAL-001-vision]]\"]")
    try fr("FR-010-names-a-missing-goal", "Names a missing goal", "draft", level: "epic", lane: "backbone", goal: "[\"[[GOAL-099-x]]\"]")
    try fr("FR-011-unquoted-goal", "Unquoted goal", "draft", level: "epic", lane: "backbone", goal: "[[GOAL-002-served]]")
    try fr("FR-012-scalar-goal", "Scalar goal", "draft", level: "epic", lane: "backbone", goal: "\"[[GOAL-002-served]]\"")
    // GOAL-006: a draft epic and an agreed feature
    try fr("FR-013-draft-epic-for-six", "Draft epic for six", "draft", level: "epic", lane: "backbone",
           goal: "[\"[[GOAL-006-draft-epic-agreed-feature]]\"]")
    try fr("FR-014-agreed-feature-for-six", "Agreed feature for six", "accepted", level: "feature", lane: "backbone",
           parent: "[\"[[FR-013-draft-epic-for-six]]\"]", goal: "[\"[[GOAL-006-draft-epic-agreed-feature]]\"]")
    // the only requirement serving GOAL-007: another notation, no column
    try fr("FR-015-ears-shall", "The system shall", "draft", notation: "ears", level: "requirement", goal: "[\"[[GOAL-007-ears-only]]\"]")
    // a use case is a functional requirement in the use-case notation
    try fr("UC-001-borrow", "Borrow", "draft", notation: "use-case", level: "sea", goal: "[\"[[GOAL-004-draft]]\"]")
    return wiki
}

@Suite struct GoalMatrixTests {
    @Test func theRuleHelper() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        #expect(matrix.enablers.map(\.id) == ["FR-003", "FR-005"])
        #expect(matrix.untraced == ["FR-002", "FR-009", "FR-010"])
        #expect(matrix.servedBy(goal: "GOAL-002").map(\.id) == ["FR-001", "FR-004", "FR-006", "FR-011", "FR-012"])
        #expect(matrix.goals.map(\.id) == ["GOAL-002", "GOAL-003", "GOAL-004", "GOAL-005", "GOAL-006", "GOAL-007"])
    }

    @Test func columnsAreEpicsAndUseCasesEnablersLast() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        #expect(matrix.columns.map(\.id) == ["FR-001", "FR-002", "FR-006", "FR-007", "FR-009", "FR-010", "FR-011",
                                             "FR-012", "FR-013", "UC-001", "FR-003", "FR-005"])
    }

    @Test func enablersByLane() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        let enablers = Set(matrix.enablers.map(\.id))
        for column in matrix.columns {
            #expect(enablers.contains(column.id) == ["FR-003", "FR-005"].contains(column.id), "\(column.id)")
        }
        // lane platform, but a goal named: no enabler
        #expect(!enablers.contains("FR-007"))
    }

    @Test func untracedEpicIsMarkedNotAnEnabler() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        #expect(matrix.untraced.contains("FR-002"))
        #expect(!matrix.enablers.contains { $0.id == "FR-002" })
        #expect(matrix.columns.contains { $0.id == "FR-002" })
    }

    @Test func goalWithoutAMarkStandsOut() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        #expect(matrix.gaps == ["GOAL-003"])
        #expect(matrix.columns.allSatisfy { !matrix.marked(goal: "GOAL-003", column: $0.id) })
        #expect(matrix.servedBy(goal: "GOAL-003").isEmpty)
        #expect(matrix.marked(goal: "GOAL-002", column: "FR-001"))
        #expect(!matrix.marked(goal: "GOAL-002", column: "FR-002"))
        #expect(!matrix.marked(goal: "GOAL-002", column: "no-such"))
    }

    @Test func goalServedOnlyByFeaturesIsNoGap() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        #expect(!matrix.gaps.contains("GOAL-005"))
        #expect(matrix.columns.allSatisfy { !matrix.marked(goal: "GOAL-005", column: $0.id) })
        #expect(matrix.servedBy(goal: "GOAL-005").map(\.id) == ["FR-008"])
        #expect(matrix.servedWithoutColumn(goal: "GOAL-005").map(\.id) == ["FR-008"])
    }

    @Test func goalServedOnlyByAnotherNotationIsNoGap() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let matrix = try wiki.projections().goalMatrix()
        #expect(!matrix.gaps.contains("GOAL-007"))
        #expect(matrix.servedBy(goal: "GOAL-007").map(\.id) == ["FR-015"])
        #expect(matrix.columns.allSatisfy { !matrix.marked(goal: "GOAL-007", column: $0.id) })
        #expect(!matrix.enablers.contains { $0.id == "FR-015" })
        #expect(!matrix.untraced.contains("FR-015"))
        // it is a draft: with drafts hidden the goal is a gap
        #expect(matrix.acceptedGaps.contains("GOAL-007"))
    }

    @Test func agreedOnlyCountsAgreedPages() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let all = try wiki.projections().goalMatrix()
        let agreed = try wiki.projections(agreedOnly: true).goalMatrix()
        // GOAL-005: only a draft feature, so with drafts hidden it is a gap
        #expect(all.acceptedGaps.contains("GOAL-005"))
        #expect(agreed.gaps.contains("GOAL-005"))
        // GOAL-006: a draft epic (a mark) and an agreed feature: no gap either way
        #expect(!all.gaps.contains("GOAL-006") && !all.acceptedGaps.contains("GOAL-006"))
        #expect(!agreed.gaps.contains("GOAL-006"))
        #expect(agreed.servedBy(goal: "GOAL-006").map(\.id) == ["FR-014"])
        #expect(agreed.servedWithoutColumn(goal: "GOAL-006").map(\.id) == ["FR-014"])
        #expect(agreed.columns.allSatisfy { $0.status == "accepted" })
    }

    @Test func agreedOnlyHidesDraftsAndFindsNewGaps() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let all = try wiki.projections().goalMatrix()
        let agreed = try wiki.projections(agreedOnly: true).goalMatrix()
        #expect(all.goals.contains { $0.id == "GOAL-004" })
        #expect(agreed.goals.allSatisfy { $0.status == "accepted" })
        #expect(!agreed.goals.contains { $0.id == "GOAL-004" })
        #expect(agreed.columns.map(\.id) == ["FR-001", "FR-003"])
        #expect(agreed.gaps == ["GOAL-003", "GOAL-005", "GOAL-007"])
        #expect(all.gaps == ["GOAL-003"])
        #expect(all.acceptedGaps.isSuperset(of: agreed.gaps))
    }

    @Test func everyMarkIsNamedOnBothPages() throws {
        let wiki = try goalWiki()
        defer { wiki.remove() }
        let store = WikiStore(root: try Preflight.open(wiki.url))
        for agreedOnly in [false, true] {
            let matrix = Projections(store: store, metamodel: store.metamodel, agreedOnly: agreedOnly).goalMatrix()
            var marks = 0
            for goal in matrix.goals {
                for column in matrix.columns where matrix.marked(goal: goal.id, column: column.id) {
                    marks += 1
                    // the requirement names the goal in `goal:`, and the goal's row lists the requirement
                    // `references` also reads a link written without quotes, which the store's link lists do not count
                    #expect((column.references["goal"] ?? []).contains { $0.name == goal.stem }, "\(column.id) names \(goal.id)")
                    #expect(matrix.servedBy(goal: goal.id).contains { $0.id == column.id }, "\(goal.id) lists \(column.id)")
                }
                for page in matrix.servedBy(goal: goal.id) where matrix.columns.contains(where: { $0.id == page.id }) {
                    #expect(matrix.marked(goal: goal.id, column: page.id))
                }
            }
            #expect(marks > 0)
        }
    }

    @Test func goldenFixtureHasOneMarkedGoal() throws {
        let matrix = try projections("basic").goalMatrix()
        #expect(matrix.goals.map(\.id) == ["GOAL-002"])
        #expect(matrix.columns.map(\.id) == ["FR-001", "FR-006"])
        #expect(matrix.enablers.map(\.id) == ["FR-006"])
        #expect(matrix.marked(goal: "GOAL-002", column: "FR-001"))
    }
}
