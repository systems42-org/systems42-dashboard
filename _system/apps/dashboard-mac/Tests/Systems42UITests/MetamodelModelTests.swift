import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor
private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

@MainActor
private func session(copy url: URL) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(url))
}

private func edit(_ url: URL, _ file: String, _ change: (String) -> String) throws {
    let path = url.appending(path: file)
    try change(String(contentsOf: path, encoding: .utf8)).write(to: path, atomically: true, encoding: .utf8)
}

@MainActor @Suite struct MetamodelModelTests {
    @Test func sevenKinds() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        #expect(m.kinds == ["Types", "Relations", "Frameworks", "Projections", "Rules", "Anchors", "Notations"])
        for kind in m.kinds { #expect(!m.entries(of: kind).isEmpty, "\(kind)") }
        #expect(m.entries(of: "Nonsense").isEmpty)
    }

    @Test func aKindWithoutEntriesIsListedAndEmpty() async throws {
        let copy = try Fixture.tempCopy("basic")
        try FileManager.default.removeItem(at: copy.appending(path: "_system/metamodel/notations"))
        let m = MetamodelModel(session: try await session(copy: copy))
        #expect(m.kinds.count == 7)
        #expect(m.entries(of: "Notations").isEmpty)
        #expect(!m.entries(of: "Types").isEmpty)
    }

    @Test func seventeenTypesInSectionOrder() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let types = m.entries(of: "Types")
        #expect(types.count == 17)
        #expect(types.first?.name == "goal")
        #expect(types.last?.name == "source")
        for entry in types { #expect(!entry.definition.isEmpty, "\(entry.name)") }
    }

    @Test func typeEntryShowsItsFields() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let goal = try #require(m.entries(of: "Types").first { $0.name == "goal" })
        let stereotype = try #require(goal.fields.first { $0.name == "stereotype" })
        #expect(stereotype.values == ["vision", "objective"])
        #expect(stereotype.doc == "vision = the one roof; objective = a PAM sub-goal")
        #expect(goal.facts.contains { $0.label == "Prefix" && $0.value == "GOAL" })
        #expect(goal.facts.contains { $0.label == "Folder" && $0.value == "wiki/goals" })
        #expect(goal.facts.contains { $0.label == "Section" && $0.value.contains("Vision") })
        let anchors = try #require(goal.groups.first { $0.title == "Anchors" })
        #expect(anchors.links.map(\.name).contains("pam"))
        let projections = try #require(goal.groups.first { $0.title == "Projections" })
        #expect(projections.links.map(\.name) == ["goal-tree", "goal-coverage"])
    }

    @Test func aTypeEntryListsItsRelations() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let goal = try #require(m.entries(of: "Types").first { $0.name == "goal" })
        let relations = try #require(goal.groups.first { $0.title == "Relations" })
        #expect(relations.links.map(\.name).contains("parent"))
        #expect(relations.links.allSatisfy { $0.kind == "Relations" })
    }

    @Test func everyAnchorLinkLeadsToAnEntry() async throws {
        var checked = 0
        for fixture in Fixture.names {
            let s = try await session(fixture)
            let m = MetamodelModel(session: s)
            for folder in s.store.folders() {
                for page in s.store.pages(in: folder) {
                    let links = page.bodyLinks + page.fieldLinks.values.flatMap { $0 }
                    for link in links {
                        guard case .anchor = s.store.resolve(link) else { continue }
                        let target = s.store.resolve(link)
                        let entry = try #require(m.entry(for: target), "\(fixture) \(page.id) \(link.name)")
                        #expect(!entry.definition.isEmpty, "\(fixture) \(page.id) \(link.name)")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked > 0)
    }

    @Test func anchorEntryNamesItsTypes() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let pam = try #require(m.entry(for: .anchor("PAM")))
        #expect(pam.kind == "Anchors")
        #expect(pam.title == "PAM")
        let types = try #require(pam.groups.first { $0.title == "Types" })
        #expect(types.links.map(\.name).contains("goal"))
        #expect(types.links.allSatisfy { $0.kind == "Types" })
    }

    @Test func anAnchorEntryHasItsOutsideReference() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let madr = try #require(m.entry(for: .anchor("MADR")))
        #expect(madr.reference?.scheme == "https")
    }

    @Test func metamodelLinksLeadToTheirEntries() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        #expect(m.entry(for: .metamodel("parent"))?.kind == "Relations")
        #expect(m.entry(for: .metamodel("goal-tree"))?.kind == "Projections")
        #expect(m.entry(for: .metamodel("req42"))?.kind == "Frameworks")
        #expect(m.entry(for: .metamodel("nothing-like-it")) == nil)
        #expect(m.entry(for: .missing) == nil)
        #expect(m.entry(for: .source("SRC-001")) == nil)
        #expect(m.entry(for: .page(PageRef(folder: "goals", stem: "x"))) == nil)
    }

    @Test func aboutThisSection() async throws {
        let s = try await session("basic")
        let m = MetamodelModel(session: s)
        let section = try #require(s.metamodel.sections.first { $0.folders.contains("functional-requirements") })
        #expect(m.entries(forSection: section.id).map(\.name).contains("functional-requirement"))
        #expect(m.entries(forSection: "nope").isEmpty)
    }

    @Test func exampleIsALivePage() async throws {
        let s = try await session("basic")
        let m = MetamodelModel(session: s)
        let goals = Set(s.store.pages(in: "goals").map(\.ref))
        #expect(goals.count == 2)
        let example = try #require(m.example(forType: "goal"))
        #expect(goals.contains(example.ref))
        #expect(m.example(forType: "nonsense") == nil)
        let entry = try #require(m.entries(of: "Types").first { $0.name == "goal" })
        #expect(entry.example?.ref == example.ref)
        #expect(entry.exampleText.contains(example.id))
    }

    @Test func aTypeWithoutPagesHasNoExample() async throws {
        let copy = try Fixture.tempCopy("basic")
        try FileManager.default.removeItem(at: copy.appending(path: "wiki/goals"))
        try FileManager.default.createDirectory(at: copy.appending(path: "wiki/goals"), withIntermediateDirectories: true)
        let m = MetamodelModel(session: try await session(copy: copy))
        #expect(m.example(forType: "goal") == nil)
        let entry = try #require(m.entries(of: "Types").first { $0.name == "goal" })
        #expect(entry.example == nil)
        #expect(entry.exampleText == MetamodelModel.noExample)
    }

    @Test func fieldHelpComesFromTheMetamodel() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        #expect(m.fieldHelp(type: "goal", field: "metric") == "the single PAM indicator; empty for a vision")
        #expect(m.fieldHelp(type: "goal", field: "nonsense") == nil)
        #expect(m.fieldHelp(type: "nonsense", field: "metric") == nil)
        #expect(m.fieldHelp(type: "goal", field: "baseline") == nil)
        #expect(m.fieldValues(type: "goal", field: "stereotype") == ["vision", "objective"])
    }

    @Test func noNoticeWhenSupported() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        #expect(m.versionNotice == nil)
    }

    @Test func noticeNamesBothVersions() async throws {
        let copy = try Fixture.tempCopy("basic")
        try edit(copy, "_system/metamodel/meta-metamodel.md") { $0.replacingOccurrences(of: "version: 0.1", with: "version: 9.9") }
        let m = MetamodelModel(session: try await session(copy: copy))
        let notice = try #require(m.versionNotice)
        #expect(notice.explanation.contains("9.9"))
        #expect(notice.explanation.contains("0.1"))
        #expect(notice.line.contains("9.9"))
    }

    @Test func missingVersionHasItsOwnWording() async throws {
        let unsupported = try Fixture.tempCopy("basic")
        try edit(unsupported, "_system/metamodel/meta-metamodel.md") { $0.replacingOccurrences(of: "version: 0.1", with: "version: 9.9") }
        let missing = try Fixture.tempCopy("basic")
        try edit(missing, "_system/metamodel/meta-metamodel.md") { $0.replacingOccurrences(of: "version: 0.1\n", with: "") }
        let a = try #require(MetamodelModel(session: try await session(copy: unsupported)).versionNotice)
        let b = try #require(MetamodelModel(session: try await session(copy: missing)).versionNotice)
        #expect(a.line != b.line)
        #expect(b.explanation.contains("0.1"))
        #expect(!b.explanation.contains("9.9"))
    }

    @Test func textsAreTheWikisTexts() async throws {
        let copy = try Fixture.tempCopy("basic")
        let s = try await session(copy: copy)
        let m = MetamodelModel(session: s)
        let before = try #require(m.entry(for: .anchor("PAM")))
        #expect(before.definition.hasPrefix("A lightweight goal frame"))
        try edit(copy, "_system/anchors/pam.md") { $0.replacingOccurrences(of: "A lightweight goal frame", with: "A changed goal frame") }
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        let after = try #require(m.entry(for: .anchor("PAM")))
        #expect(after.definition.hasPrefix("A changed goal frame"))
    }

    @Test func metamodelGraphMatchesGolden() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let got = try JSONSerialization.jsonObject(with: JSONEncoder().encode(m.graph)) as? NSDictionary
        let want = try Golden.json("basic", "diagrams/metamodel-graph.json") as? NSDictionary
        #expect(got != nil)
        #expect(got == want)
    }

    @Test func graphOutlineGroupsTypesBySection() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        let outline = m.graphOutline
        let first = try #require(outline.groups.first)
        #expect(first.title.hasPrefix("R1"))
        #expect(first.lines.contains { $0.contains("Goal") })
        #expect(outline.groups.flatMap(\.lines).count == 17)
        #expect(outline.relations.contains { $0.contains("parent") })
    }

    @Test func showingATargetSelectsItsEntry() async throws {
        let m = MetamodelModel(session: try await session("basic"))
        m.show(.anchor("PAM"))
        #expect(m.selectedKind == "Anchors")
        #expect(m.selectedEntry?.title == "PAM")
        m.show(.metamodel("goal-tree"))
        #expect(m.selectedKind == "Projections")
        #expect(m.selectedEntry?.name == "goal-tree")
        m.show(.missing)
        #expect(m.selectedEntry?.name == "goal-tree")
    }

    @Test func showingASectionSelectsItsTypes() async throws {
        let s = try await session("basic")
        let m = MetamodelModel(session: s)
        let section = try #require(s.metamodel.sections.first { $0.folders.contains("functional-requirements") })
        m.show(section: section.id)
        #expect(m.selectedKind == "Types")
        #expect(m.selectedEntry?.name == "functional-requirement")
        #expect(m.shownEntries.map(\.name) == ["functional-requirement"])
        m.showAll()
        #expect(m.shownEntries.count == 17)
    }

    @Test func theVersionExplanationCanBeShown() async throws {
        let copy = try Fixture.tempCopy("basic")
        try edit(copy, "_system/metamodel/meta-metamodel.md") { $0.replacingOccurrences(of: "version: 0.1", with: "version: 9.9") }
        let m = MetamodelModel(session: try await session(copy: copy))
        m.showVersionNotice()
        #expect(m.showsVersionNotice)
        m.select(kind: "Types")
        #expect(!m.showsVersionNotice)
    }

    @Test func theSessionKeepsOneModel() async throws {
        let s = try await session("basic")
        #expect(s.explainer === s.explainer)
    }
}

@MainActor @Suite struct FieldHelpTests {
    @Test func helpJoinsDocAndValues() {
        #expect(FieldHelp.text(doc: "what it is", values: ["a", "b"]) == "what it is\nValues: a, b")
        #expect(FieldHelp.text(doc: nil, values: ["a"]) == "Values: a")
        #expect(FieldHelp.text(doc: "what it is", values: []) == "what it is")
        #expect(FieldHelp.text(doc: nil, values: []) == nil)
        #expect(FieldHelp.text(doc: "", values: []) == nil)
    }

    @Test func theHeadOfAPageCarriesFieldHelp() async throws {
        let s = await WikiSession.open(try Preflight.open(Fixture.url("basic")))
        let ref = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        let m = try #require(PageModel(session: s, ref: ref))
        #expect(m.headHelp.count == m.head.count)
        let status = try #require(m.head.firstIndex { $0.label == "Status" })
        #expect(m.headHelp[status]?.hasPrefix("Values: draft") == true)
        #expect(m.headHelp.contains { $0 != nil && $0 != m.headHelp[status] })
    }
}
