import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

@Suite struct RelationRulesTests {
    @Test func readsTypesAndRelationsFromTheMetamodel() {
        let rules = RelationRules.read(root: Fixture.url("basic"))
        #expect(rules.issueFolder == "issues")
        #expect(rules.sourceIdStart == "SRC-")
        #expect(rules.relations["drivers"]?.field == "drivers")
        #expect(rules.relations["shaped-by"]?.field == "decisions")
        #expect(rules.relations["drivers"]?.edges.contains(
            RelationRules.Edge(from: "building-blocks", to: "quality-requirements")) == true)
        #expect(rules.relations["realizes"]?.edges.contains(
            RelationRules.Edge(from: "runtime-scenarios", to: "activity-models")) == true)
    }

    @Test func aWikiWithoutMetamodelHasNoRulesAndStillReads() throws {
        let (url, store) = try tempStore("basic")
        try FileManager.default.removeItem(at: url.appending(path: "_system/metamodel"))
        try FileManager.default.createDirectory(at: url.appending(path: "_system/metamodel"), withIntermediateDirectories: false)
        store.reload(changed: nil)
        #expect(RelationRules.read(root: url).relations.isEmpty)
        #expect(store.pages(in: "domain-terms").count == 4)
        #expect(store.openIssues(for: ref("domain-terms", "DT-001-book")).isEmpty)
        #expect(store.relations(of: ref("domain-terms", "DT-001-book")).traced.isEmpty)
    }

    @Test func theIssueFolderComesFromTheTypePage() throws {
        let (url, store) = try tempStore("hostile")
        let fm = FileManager.default
        try fm.moveItem(at: url.appending(path: "wiki/issues"), to: url.appending(path: "wiki/tickets"))
        let typePage = url.appending(path: "_system/metamodel/types/type-issue.md")
        let text = try String(contentsOf: typePage, encoding: .utf8).replacingOccurrences(of: "wiki/issues", with: "wiki/tickets")
        try text.write(to: typePage, atomically: true, encoding: .utf8)
        store.reload(changed: nil)
        #expect(store.openIssues(for: ref("domain-terms", "DT-906-fine")).map(\.id) == ["ISS-900"])
    }

    @Test func theSourcePrefixComesFromTheTypePage() throws {
        let (url, store) = try tempStore("basic")
        try "---\nid: QQ-001\ntitle: S\n---\n".write(
            to: url.appending(path: "raw/sources/QQ-001-s.md"), atomically: true, encoding: .utf8)
        let typePage = url.appending(path: "_system/metamodel/types/type-source.md")
        let text = try String(contentsOf: typePage, encoding: .utf8).replacingOccurrences(of: "prefix: SRC", with: "prefix: QQ")
        try text.write(to: typePage, atomically: true, encoding: .utf8)
        store.reload(changed: nil)
        #expect(store.resolve(Wikilink(target: "QQ-001", label: nil, heading: nil)) == .source("QQ-001-s"))
    }

    @Test func noSourceFileNamesAFolderOfTheWiki() throws {
        var folders = Set<String>()
        for fixture in ["basic", "arc42-views"] {
            let wiki = Fixture.url(fixture).appending(path: "wiki")
            folders.formUnion(try FileManager.default.contentsOfDirectory(atPath: wiki.path).filter { !$0.hasPrefix(".") })
        }
        #expect(folders.count >= 10)
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Systems42Kit")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 5)
        for file in files {
            let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            for folder in folders {
                #expect(!text.contains("\"\(folder)\""), "\(file) names the folder \(folder)")
            }
        }
    }
}
