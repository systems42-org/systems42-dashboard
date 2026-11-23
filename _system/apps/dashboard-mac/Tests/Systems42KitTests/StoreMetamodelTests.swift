import Testing
import Foundation
import Systems42TestSupport
@testable import Systems42Kit

@Suite struct StoreMetamodelTests {
    @Test func storeExposesTheMetamodelOfItsSnapshot() throws {
        let root = try Preflight.open(Fixture.url("tailored"))
        let store = WikiStore(root: root)
        let fromStore = store.metamodel.sections.map(\.id)
        #expect(fromStore == Metamodel.load(root).sections.map(\.id))
        #expect(fromStore.contains("A6"))
    }

    @Test func issueSectionIsTheOneListingTheIssueType() throws {
        let root = try Preflight.open(Fixture.url("tailored"))
        let section = try #require(Metamodel.load(root).issueSection)
        #expect(section.id == "C6")
        #expect(section.title == "Open Points")
    }
}

@Suite struct RelationLookupTests {
    @Test func aRelationIsFoundByItsStoredField() throws {
        let m = Metamodel.load(try Preflight.open(Fixture.url("basic")))
        let parent = try #require(m.relation(storedIn: "parent"))
        #expect(parent.storedField == "parent")
        #expect(parent.inverse == "children")
        #expect(m.relation(storedIn: "no-such-field") == nil)
    }
}

@Suite struct LifecycleTests {
    @Test func lifecyclesComeFromTheMetamodel() throws {
        let m = Metamodel.load(try Preflight.open(Fixture.url("basic")))
        #expect(m.lifecycles["content"] == ["draft", "review", "accepted", "deprecated"])
        #expect(m.lifecycles["issue"] == ["open", "in-progress", "resolved", "wontfix"])
        #expect(m.type(named: "functional-requirement")?.lifecycle == "content")
        #expect(m.type(named: "issue")?.lifecycle == "issue")
    }

    @Test func aSectionTakesTheLifecycleOfItsTypes() throws {
        let m = Metamodel.load(try Preflight.open(Fixture.url("basic")))
        let fr = try #require(m.sections.first { $0.folders.contains("functional-requirements") })
        #expect(m.lifecycle(of: fr) == ["draft", "review", "accepted", "deprecated"])
        let issues = try #require(m.issueSection)
        #expect(m.lifecycle(of: issues)?.first == "open")
    }

    @Test func noMetamodelGivesNoLifecycles() throws {
        let copy = try Fixture.tempCopy("basic")
        try FileManager.default.removeItem(at: copy.appending(path: "_system/metamodel/meta-metamodel.md"))
        let m = Metamodel.load(try Preflight.open(copy))
        #expect(m.lifecycles.isEmpty)
        let fr = try #require(m.sections.first { $0.folders.contains("functional-requirements") })
        #expect(m.lifecycle(of: fr) == nil)
    }
}
