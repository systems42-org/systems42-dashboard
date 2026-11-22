import Foundation
import Testing
import Systems42TestSupport

@Suite struct GoldenTests {
    @Test(arguments: Fixture.names)
    func goldenExistsForEveryFixture(name: String) throws {
        for file in ["search.json", "sections.json", "pages.json", "metamodel.json"] {
            #expect(Golden.exists(name, file), "\(name) lacks \(file)")
            _ = try Golden.json(name, file)
        }
    }

    @Test func goldenPagesMatchFixtureFiles() throws {
        let basic = try #require(Golden.json("basic", "pages.json") as? [String: Any])
        let search = try #require(Golden.json("search", "pages.json") as? [String: Any])
        #expect(basic.count == 15)
        #expect(search.count == 19)
    }

    @Test func goldenPagesHaveTheDocumentedKeys() throws {
        let pages = try #require(Golden.json("basic", "pages.json") as? [String: [String: Any]])
        for (id, page) in pages {
            #expect(Set(page.keys) == ["id", "title", "status", "type", "links_to", "linked_from"], "\(id)")
            #expect(page["id"] as? String == id)
        }
    }

    @Test func goldenMetamodelHasSeventeenTypes() throws {
        let model = try #require(Golden.json("basic", "metamodel.json") as? [String: Any])
        let types = try #require(model["types"] as? [[String: Any]])
        #expect(types.count == 17)
        #expect(types.first?["name"] as? String == "goal")
        #expect(types.last?["name"] as? String == "source")
        let frameworks = try #require(model["frameworks"] as? [[String: Any]])
        #expect(frameworks.compactMap { $0["name"] as? String } == ["req42", "commons", "arc42"])
    }

    @Test func goldenMetamodelHasEverySection() throws {
        let model = try #require(Golden.json("basic", "metamodel.json") as? [String: Any])
        for key in ["relations", "projections", "rules", "anchors"] {
            let list = try #require(model[key] as? [[String: Any]])
            #expect(!list.isEmpty, "\(key) is empty")
        }
        let version = try #require(model["version"] as? [String: Any])
        #expect(version["state"] as? String == "supported")
    }

    @Test(arguments: Fixture.names)
    func goldenSectionsListEighteenSections(name: String) throws {
        let sections = try #require(Golden.json(name, "sections.json") as? [String: [String: Any]])
        #expect(sections.count == 18)
        for (id, section) in sections {
            #expect(Set(section.keys) == ["title", "area", "folders", "pages"], "\(id)")
        }
    }

    @Test func goldenSectionsListThePagesOfBasic() throws {
        let sections = try #require(Golden.json("basic", "sections.json") as? [String: [String: Any]])
        let goals = try #require(sections["R1"])
        #expect(goals["title"] as? String == "Vision & Goals")
        #expect(goals["area"] as? String == "req42")
        #expect(goals["folders"] as? [String] == ["goals"])
        #expect((goals["pages"] as? [String])?.count == 2)
    }

    @Test(arguments: Fixture.names)
    func everyPageSitsInOneSection(name: String) throws {
        let pages = try #require(Golden.json(name, "pages.json") as? [String: Any])
        let sections = try #require(Golden.json(name, "sections.json") as? [String: [String: Any]])
        let listed = sections.values.flatMap { $0["pages"] as? [String] ?? [] }
        #expect(listed.count == Set(listed).count, "a page is listed twice")
        #expect(Set(listed) == Set(pages.keys))
    }

    @Test(arguments: Fixture.names)
    func searchRecordsMatchPages(name: String) throws {
        let search = try #require(Golden.json(name, "search.json") as? [String: Any])
        let records = try #require(search["records"] as? [[String: Any]])
        let pages = try #require(Golden.json(name, "pages.json") as? [String: Any])
        #expect(Set(records.compactMap { $0["id"] as? String }) == Set(pages.keys))
    }

    @Test func goldenDiagramsExistWhereTheFixtureHasPages() throws {
        #expect(Golden.diagrams("basic").contains("goals.mmd"))
        #expect(Golden.diagrams("basic").contains("term-network.json"))
        #expect(Golden.diagrams("basic").contains("metamodel-graph.json"))
        #expect(Golden.diagrams("arc42-views").contains("building-blocks.mmd"))
        #expect(Golden.diagrams("arc42-views").contains("deployment.mmd"))
        #expect(Golden.diagrams("domain-model").contains("data-model.mmd"))
        #expect(try Golden.text("basic", "diagrams/goals.mmd").hasPrefix("graph TD"))
    }

    @Test(arguments: Fixture.names)
    func goldenFilesHoldNothingVolatile(name: String) throws {
        let files = ["search.json", "sections.json", "pages.json", "metamodel.json"]
            + Golden.diagrams(name).map { "diagrams/\($0)" }
        for file in files {
            let text = try Golden.text(name, file)
            #expect(!text.contains("127.0.0.1"), "\(name)/\(file)")
            #expect(!text.contains("/Users/"), "\(name)/\(file)")
            #expect(!text.contains("nonce"), "\(name)/\(file)")
        }
    }
}
