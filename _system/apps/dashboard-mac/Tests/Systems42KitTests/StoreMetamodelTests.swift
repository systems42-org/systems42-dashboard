import Testing
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
