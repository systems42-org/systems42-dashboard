import Foundation
import Testing
import Systems42TestSupport

private func entries(_ url: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
}

private func markdownCount(_ url: URL) -> Int {
    let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
        .allObjects as? [URL] ?? []
    return files.filter { $0.pathExtension == "md" }.count
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

@Suite struct FixtureTests {
    @Test(arguments: Fixture.names)
    func fixturesAreComplete(name: String) {
        let root = Fixture.url(name)
        for path in ["wiki", "raw", "raw/sources", "_system/wiki.yaml", "_system/metamodel", "_system/anchors"] {
            #expect(exists(root.appending(path: path)), "\(name) lacks \(path)")
        }
    }

    @Test func basicFixtureCounts() {
        let wiki = Fixture.url("basic").appending(path: "wiki")
        #expect(markdownCount(wiki.appending(path: "functional-requirements")) == 6)
        #expect(markdownCount(wiki.appending(path: "domain-terms")) == 4)
        #expect(markdownCount(wiki.appending(path: "goals")) == 2)
        #expect(markdownCount(wiki.appending(path: "stakeholders")) == 2)
        #expect(markdownCount(wiki.appending(path: "decisions")) == 1)
        #expect(markdownCount(wiki) == 15)
    }

    @Test func searchFixtureCounts() {
        let wiki = Fixture.url("search").appending(path: "wiki")
        #expect(markdownCount(wiki.appending(path: "functional-requirements")) == 9)
        #expect(markdownCount(wiki.appending(path: "domain-terms")) == 3)
        #expect(markdownCount(wiki.appending(path: "issues")) == 2)
        #expect(markdownCount(wiki.appending(path: "stakeholders")) == 5)
        #expect(markdownCount(wiki) == 19)
    }

    @Test func metamodelFixtureHasSeventeenTypes() {
        let types = Fixture.url("basic").appending(path: "_system/metamodel/types")
        let names = entries(types).map(\.lastPathComponent)
            .filter { $0.hasPrefix("type-") && $0.hasSuffix(".md") }
        #expect(names.count == 17)
    }

    @Test func fixtureWikiYamlNamesTheSystem() throws {
        for name in Fixture.names {
            let text = try String(contentsOf: Fixture.url(name).appending(path: "_system/wiki.yaml"), encoding: .utf8)
            #expect(text.contains("system_name:"), "\(name) wiki.yaml has no system_name")
        }
    }

    @Test func sourceFileNamesACommit() throws {
        let url = Fixture.url("basic").deletingLastPathComponent().appending(path: "SOURCE")
        let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil)
    }
}
