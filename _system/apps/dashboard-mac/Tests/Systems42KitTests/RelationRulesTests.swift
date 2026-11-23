import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

@Suite struct RelationRulesTests {
    @Test func readsTypesAndRelationsFromTheMetamodel() throws {
        let rules = try loadMetamodel(fixture: "basic").relationRules
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
        #expect(try loadMetamodel(url).relationRules.relations.isEmpty)
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

    @Test func theSourceFolderComesFromTheTypePage() throws {
        let (url, store) = try tempStore("basic")
        let fm = FileManager.default
        try fm.createDirectory(at: url.appending(path: "raw/records"), withIntermediateDirectories: true)
        try "---\nid: SRC-001\ntitle: S\n---\n".write(
            to: url.appending(path: "raw/records/SRC-001-s.md"), atomically: true, encoding: .utf8)
        let link = Wikilink(target: "SRC-001-s", label: nil, heading: nil)
        store.reload(changed: nil)
        #expect(store.resolve(link) == .missing)
        let typePage = url.appending(path: "_system/metamodel/types/type-source.md")
        let text = try String(contentsOf: typePage, encoding: .utf8).replacingOccurrences(of: "raw/sources", with: "raw/records")
        try text.write(to: typePage, atomically: true, encoding: .utf8)
        store.reload(changed: nil)
        #expect(store.resolve(link) == .source("SRC-001-s"))
    }

    @Test func aStepMessageIsNotALink() throws {
        let (url, store) = try tempStore("arc42-views")
        let scenario = url.appending(path: "wiki/runtime-scenarios/RS-009-message.md")
        func write(_ message: String) throws {
            try """
            ---
            id: RS-009
            type: runtime-scenario
            title: Message
            status: draft
            steps:
              - {from: "[[BB-003-console]]", to: "[[BB-004-account]]", message: \(message)}
            ---
            """.write(to: scenario, atomically: true, encoding: .utf8)
            store.reload(changed: nil)
        }
        try write("BB-002-identity")
        #expect(store.relations(of: ref("building-blocks", "BB-002-identity")).traced
            .contains(ref("runtime-scenarios", "RS-009-message")) == false)
        #expect(store.relations(of: ref("building-blocks", "BB-004-account")).traced
            .contains(ref("runtime-scenarios", "RS-009-message")))
        try write("\"[[BB-002-identity]]\"")
        // a link in a message is still not an end of the step
        #expect(store.relations(of: ref("building-blocks", "BB-002-identity")).traced
            .contains(ref("runtime-scenarios", "RS-009-message")) == false)
    }
}
