import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

/// The golden file names the areas as the dashboard's tiles do.
private let goldenAreas: [String: Area] = ["req42": .requirements, "arc42": .architecture, "commons": .commons]

@Suite struct CatalogTests {
    @Test(arguments: Fixture.names)
    func sectionsMatchGolden(name: String) throws {
        let model = try loadMetamodel(fixture: name)
        let golden = try #require(Golden.json(name, "sections.json") as? [String: [String: Any]])
        #expect(Set(model.sections.map(\.id)) == Set(golden.keys))
        #expect(model.sections.count == 18)
        for section in model.sections {
            let theirs = try #require(golden[section.id])
            #expect(section.title == theirs["title"] as? String, "\(section.id)")
            #expect(section.area == goldenAreas[theirs["area"] as? String ?? ""], "\(section.id)")
            #expect(section.folders.sorted() == theirs["folders"] as? [String], "\(section.id)")
        }
    }

    @Test func sectionsGroupByAreaInDiagramOrder() throws {
        let model = try loadMetamodel(fixture: "basic")
        #expect(Area.allCases == [.requirements, .architecture, .commons])
        let order = model.sections.map { Area.allCases.firstIndex(of: $0.area)! }
        #expect(order == order.sorted())
        #expect(model.sections.first?.area == .requirements)
        #expect(model.sections.last?.area == .commons)
    }

    @Test func sectionsKnowTheirTypesAndScope() throws {
        let model = try loadMetamodel(fixture: "basic")
        let scope = try #require(model.sections.first { $0.folders == ["context", "external-interfaces"] })
        #expect(scope.types == ["context", "external-interface"])
        #expect(scope.scope == "in")
        let out = model.sections.filter { $0.scope == "out" }
        #expect(out.count == 3)
        #expect(out.allSatisfy { $0.folders.isEmpty && $0.types.isEmpty })
    }

    @Test func renamedAndAddedSectionAppear() throws {
        let tailored = try loadMetamodel(fixture: "tailored")
        let basic = try loadMetamodel(fixture: "basic")
        #expect(tailored.sections.count == basic.sections.count + 1)
        let added = try #require(tailored.sections.first { $0.title == "Risks and Technical Debt" })
        #expect(added.folders == ["risks"])
        #expect(added.types == ["risk"])
        #expect(added.area == .architecture)
        #expect(added.scope == "in")
        #expect(tailored.type(forFolder: "wiki/risks")?.name == "risk")
        let renamed = try #require(basic.sections.first { $0.title == "Issues" })
        #expect(tailored.sections.first { $0.id == renamed.id }?.title == "Open Points")
        #expect(!tailored.sections.contains { $0.title == "Issues" })
        // the added section sits with its area, after the section it follows
        let ids = tailored.sections.map(\.id)
        let anchor = try #require(tailored.sections.first { $0.types == ["crosscutting-concept"] })
        #expect(ids.firstIndex(of: added.id) == ids.firstIndex(of: anchor.id)! + 1)
    }

    @Test func aSectionNamingAnUnknownAreaOrTypeIsHandled() throws {
        let url = try Fixture.tempCopy("basic")
        let page = url.appending(path: "_system/metamodel/frameworks/fw-arc42.md")
        var text = try String(contentsOf: page, encoding: .utf8)
        text = text.replacingOccurrences(of: "types: [crosscutting-concept]", with: "types: [no-such-type, crosscutting-concept]")
        try text.write(to: page, atomically: true, encoding: .utf8)
        let model = try loadMetamodel(url)
        let concepts = try #require(model.sections.first { $0.types.contains("crosscutting-concept") })
        #expect(concepts.folders == ["crosscutting-concepts"])
        try "---\ntype: metamodel\nconstruct: framework\nname: odd\narea: moon\nblocks:\n  - {id: M1, title: Moon, types: [], scope: in}\n---\n"
            .write(to: url.appending(path: "_system/metamodel/frameworks/fw-odd.md"), atomically: true, encoding: .utf8)
        #expect(try loadMetamodel(url).sections.count == 18)
    }

    @Test func aRepeatedSectionIdKeepsTheFirst() throws {
        let url = try Fixture.tempCopy("basic")
        try "---\ntype: metamodel\nconstruct: framework\nname: dup\narea: commons\nblocks:\n  - {id: C6, title: Again, types: [], scope: in}\n---\n"
            .write(to: url.appending(path: "_system/metamodel/frameworks/fw-aaa.md"), atomically: true, encoding: .utf8)
        let model = try loadMetamodel(url)
        #expect(model.sections.filter { $0.id == "C6" }.count == 1)
        #expect(model.sections.count == 18)
    }

    @Test func noMetamodelFactsInCode() throws {
        var literals = Set<String>()
        for fixture in ["basic", "arc42-views"] {
            let wiki = Fixture.url(fixture).appending(path: "wiki")
            literals.formUnion(try FileManager.default.contentsOfDirectory(atPath: wiki.path).filter { !$0.hasPrefix(".") })
        }
        let sections = try #require(Golden.json("basic", "sections.json") as? [String: [String: Any]])
        for (id, section) in sections {
            literals.insert(id)
            literals.insert(try #require(section["title"] as? String))
        }
        let model = try loadMetamodel(fixture: "basic")
        for type in model.types {
            literals.insert(type.label)
            if !type.prefix.isEmpty { literals.insert(type.prefix); literals.insert(type.prefix + "-") }
        }
        #expect(literals.count > 60)
        for id in ["R1", "A2", "C6", "DT-", "FR-", "GOAL-"] { #expect(literals.contains(id)) }

        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 10)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in literals {
                #expect(!text.contains("\"\(literal)\""), "\(file.lastPathComponent) holds the literal \(literal)")
                #expect(!text.contains("\"\(literal)-"), "\(file.lastPathComponent) holds a literal starting \(literal)-")
            }
        }
    }
}
