import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

func loadMetamodel(_ url: URL) throws -> Metamodel {
    Metamodel.load(try Preflight.open(url))
}

func loadMetamodel(fixture name: String) throws -> Metamodel {
    try loadMetamodel(Fixture.url(name))
}

/// The whitespace-normalised text, as the golden export stores it.
private func plain(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// The text without the markup the dashboard drops (wikilinks keep their label, links their text), in lower case, hyphens as spaces.
private func unmarked(_ text: String) -> String {
    var text = text
    for (pattern, template) in [
        (#"\[\[[^\]|]*\|([^\]]*)\]\]"#, "$1"), (#"\[\[([^\]]*)\]\]"#, "$1"),
        (#"\[([^\]]*)\]\(([^)]*)\)"#, "$1"), (#"[`*<>]"#, ""),
    ] {
        text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
    return plain(text.replacingOccurrences(of: "-", with: " ")).lowercased()
}

@Suite struct MetamodelTests {
    @Test func loaderReadsEveryConstruct() throws {
        let model = try loadMetamodel(fixture: "basic")
        #expect(model.types.count == 17)
        #expect(model.types.first?.name == "goal")
        #expect(model.types.last?.name == "source")
        #expect(!model.relations.isEmpty)
        #expect(!model.projections.isEmpty)
        #expect(!model.rules.isEmpty)
        for type in model.types { #expect(!type.summary.isEmpty, "\(type.name) has no summary") }
    }

    @Test func aliasesFindTheirType() throws {
        let model = try loadMetamodel(fixture: "basic")
        #expect(model.type(named: "FR")?.name == "functional-requirement")
        #expect(model.type(named: "GOAL")?.name == "goal")
        #expect(model.type(named: "type-goal")?.name == "goal")
        #expect(model.type(named: "goal")?.prefix == "GOAL")
        #expect(model.type(forFolder: "wiki/goals")?.name == "goal")
        #expect(model.type(forFolder: "goals")?.name == "goal")
        #expect(model.type(named: "nonsense") == nil)
        #expect(model.type(forFolder: "nonsense") == nil)
    }

    @Test func goalFieldsCarryTheirDoc() throws {
        let goal = try #require(try loadMetamodel(fixture: "basic").type(named: "goal"))
        let field = try #require(goal.fields.first { $0.name == "stereotype" })
        #expect(field.values == ["vision", "objective"])
        #expect(field.required)
        #expect(field.kind == "enum")
        #expect(field.doc?.isEmpty == false)
        let parent = try #require(goal.fields.first { $0.name == "parent" })
        #expect(parent.relation == "parent")
        #expect(!parent.required)
        #expect(goal.stereotypes == ["vision", "objective"])
        #expect(goal.anchors == ["PAM", "SMART", "req42"])
        #expect(goal.projections == ["goal-tree", "goal-coverage"])
        #expect(goal.block == "R1")
    }

    @Test(arguments: Fixture.names)
    func metamodelMatchesGolden(name: String) throws {
        let model = try loadMetamodel(fixture: name)
        let golden = try #require(Golden.json(name, "metamodel.json") as? [String: Any])
        func list(_ key: String) throws -> [[String: Any]] { try #require(golden[key] as? [[String: Any]]) }

        let types = try list("types")
        // The Go dashboard lists the types by a fixed framework order. Here they follow the sections.
        #expect(Set(model.types.map(\.name)) == Set(types.compactMap { $0["name"] as? String }))
        for mine in model.types {
            let theirs = try #require(types.first { $0["name"] as? String == mine.name })
            #expect(mine.label == theirs["label"] as? String)
            #expect(mine.prefix + "-NNN" == theirs["id_pattern"] as? String || theirs["id_pattern"] as? String == nil, "\(mine.name) prefix")
            #expect(mine.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == (theirs["folder"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")), "\(mine.name) folder")
            #expect(mine.block == theirs["block"] as? String ?? "", "\(mine.name) block")
            let fields = theirs["fields"] as? [[String: Any]] ?? []
            for (a, b) in zip(mine.fields, fields) {
                #expect(a.kind == b["kind"] as? String, "\(mine.name).\(a.name) kind")
                #expect(a.required == (b["required"] as? Bool ?? false), "\(mine.name).\(a.name) required")
            }
            #expect(unmarked(mine.summary) == unmarked(theirs["definition"] as? String ?? ""), "\(mine.name)")
            #expect(mine.fields.map(\.name) == (theirs["fields"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        }
        let relations = try list("relations")
        #expect(model.relations.map { $0.frontmatter["field"] } == relations.compactMap { ($0["field"] as? String).map(FieldValue.text) })
        for (mine, theirs) in zip(model.relations, relations) {
            #expect(unmarked(mine.summary) == unmarked(theirs["meaning"] as? String ?? ""), "\(mine.name)")
        }
        for (mine, golden) in [(model.projections, "projections"), (model.rules, "rules")] {
            let theirs = try list(golden)
            #expect(mine.map(\.name) == theirs.compactMap { $0["name"] as? String })
            for (a, b) in zip(mine, theirs) {
                #expect(unmarked(a.summary) == unmarked(b["summary"] as? String ?? ""), "\(a.name)")
            }
        }
        let anchors = try list("anchors")
        #expect(model.anchors.count == anchors.count)
        for theirs in anchors {
            let id = try #require(theirs["id"] as? String)
            let mine = try #require(model.anchors.first { $0.name.lowercased() == id })
            #expect(mine.title == theirs["name"] as? String)
            #expect(unmarked(mine.definition) == unmarked(theirs["definition"] as? String ?? ""), "\(id)")
            // The dashboard drops an anchor's own names from its aliases and rewrites applies-to, so only aliases are compared.
            #expect(Set(theirs["aliases"] as? [String] ?? []).isSubset(of: mine.aliases))
        }
    }

    @Test func supportedVersionIsQuiet() throws {
        #expect(try loadMetamodel(fixture: "basic").version == .supported("0.1"))
    }

    @Test func versionOutsideTheSet() throws {
        let url = try Fixture.tempCopy("basic")
        try setVersion(url, "version: 9.9")
        #expect(try loadMetamodel(url).version == .unsupported(found: "9.9", supported: ["0.1"]))
    }

    @Test func missingVersionHasItsOwnState() throws {
        let url = try Fixture.tempCopy("basic")
        try setVersion(url, nil)
        #expect(try loadMetamodel(url).version == .missing(supported: ["0.1"]))
        try FileManager.default.removeItem(at: url.appending(path: "_system/metamodel/meta-metamodel.md"))
        #expect(try loadMetamodel(url).version == .missing(supported: ["0.1"]))
    }

    @Test func versionIsReadAsText() throws {
        let url = try Fixture.tempCopy("basic")
        try setVersion(url, "version: 0.10")
        #expect(try loadMetamodel(url).version == .unsupported(found: "0.10", supported: ["0.1"]))
        try setVersion(url, "version: \"0.1\"")
        #expect(try loadMetamodel(url).version == .supported("0.1"))
    }

    @Test func aVersionFileWinsOverTheMetaMetamodel() throws {
        let url = try Fixture.tempCopy("basic")
        try "---\nversion: 3.0\n---\n".write(
            to: url.appending(path: "_system/metamodel/metamodel-version.md"), atomically: true, encoding: .utf8)
        #expect(try loadMetamodel(url).version == .unsupported(found: "3.0", supported: ["0.1"]))
    }

    @Test func anchorByAlias() throws {
        let model = try loadMetamodel(fixture: "basic")
        for name in ["MADR", "INVEST", "MoSCoW", "moscow", "Q42"] {
            let anchor = try #require(model.anchor(name), "\(name)")
            #expect(!anchor.definition.isEmpty, "\(name)")
        }
        #expect(model.anchor("gherkin")?.title.hasPrefix("Acceptance Criteria") == true)
        #expect(model.anchor("nonsense") == nil)
        #expect(model.anchor("Q42")?.reference != nil)
    }

    @Test func requirementPreset() throws {
        let model = try loadMetamodel(fixture: "basic")
        #expect(model.sortPresets(for: "functional-requirement").first?.keys.map(\.field) == ["priority", "release", "order"])
        #expect(model.sortPresets(for: "issue").first?.keys.map(\.field) == ["status", "severity"])
        #expect(model.sortPresets(for: "decision-record").first == SortPreset(label: "Newest first", keys: [SortKey(field: "decided", ascending: false)]))
        #expect(model.sortPresets(for: "constraint").isEmpty)
        #expect(model.sortPresets(for: "nonsense").isEmpty)
    }

    @Test func brokenMetamodelPageIsSkipped() throws {
        let url = try Fixture.tempCopy("basic")
        try "---\ntype: metamodel\nconstruct: type\nname: [oops\n---\n# broken\n".write(
            to: url.appending(path: "_system/metamodel/types/type-goal.md"), atomically: true, encoding: .utf8)
        let model = try loadMetamodel(url)
        #expect(model.types.count == 16)
        #expect(model.type(named: "goal") == nil)
    }

    @Test func aMissingMetamodelFolderGivesAnEmptyMetamodel() throws {
        let url = try Fixture.tempCopy("basic")
        for part in ["_system/metamodel", "_system/anchors"] {
            try FileManager.default.removeItem(at: url.appending(path: part))
            try FileManager.default.createDirectory(at: url.appending(path: part), withIntermediateDirectories: false)
        }
        let model = try loadMetamodel(url)
        #expect(model.types.isEmpty && model.sections.isEmpty && model.anchors.isEmpty)
        #expect(model.version == .missing(supported: ["0.1"]))
        #expect(model.sortPresets(for: "issue").isEmpty == false)
    }

    @Test func hostileMetamodelPagesNeverCrash() throws {
        let url = try Fixture.tempCopy("basic")
        let types = url.appending(path: "_system/metamodel/types")
        let deep = String(repeating: "[", count: 400) + String(repeating: "]", count: 400)
        let pages = [
            "type-a.md": "",
            "type-b.md": "no frontmatter at all",
            "type-c.md": "---\ntype: metamodel\nconstruct: type\n---\n",
            "type-d.md": "---\ntype: metamodel\nconstruct: type\nname: d\nfields: 7\nstereotypes: {a: b}\nblock: [x]\n---\n",
            "type-e.md": "---\ntype: metamodel\nconstruct: type\nname: e\nfolder: ../../outside\nfields: [1, [2], {name: 3}]\n---\n",
            "type-f.md": "---\ntype: metamodel\nconstruct: type\nname: f\nx: \(deep)\n---\n",
            "type-g.md": "---\n- a\n- b\n---\n",
        ]
        for (name, text) in pages { try text.write(to: types.appending(path: name), atomically: true, encoding: .utf8) }
        let model = try loadMetamodel(url)
        #expect(model.type(named: "goal") != nil)
        #expect(model.type(named: "d")?.fields.isEmpty == true)
        #expect(model.type(named: "f") == nil)
    }

    @Test func readingLeavesTheWikiUntouched() throws {
        let url = try Fixture.tempCopy("basic")
        assertUnchanged(url) { _ = try? loadMetamodel(url) }
    }

    @Test func aRepeatedTypeNameKeepsTheFirstPage() throws {
        let url = try Fixture.tempCopy("basic")
        try "---\ntype: metamodel\nconstruct: type\nname: goal\nprefix: ZZ\nfolder: wiki/zz\nlabel: Again\nblock: R1\n---\nAgain.\n"
            .write(to: url.appending(path: "_system/metamodel/types/type-zz.md"), atomically: true, encoding: .utf8)
        let model = try loadMetamodel(url)
        #expect(model.types.count == 17)
        #expect(model.types.filter { $0.name == "goal" }.count == 1)
        #expect(model.type(named: "goal")?.prefix == "GOAL")
        #expect(model.type(forFolder: "wiki/zz") == nil)
        #expect(model.sections.first { $0.id == "R1" }?.folders == ["goals"])
        #expect(model.relationRules.folders["goal"] == "wiki/goals")
    }

    @Test func aTypeFolderLeadingOutsideReadsNothingFromThere() throws {
        let url = try Fixture.tempCopy("basic")
        let outside = url.deletingLastPathComponent().appending(path: "outside-sources")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "---\nid: SRC-777\ntitle: Outside\n---\nOutside.\n".write(
            to: outside.appending(path: "SRC-777-outside.md"), atomically: true, encoding: .utf8)
        let typePage = url.appending(path: "_system/metamodel/types/type-source.md")
        try String(contentsOf: typePage, encoding: .utf8).replacingOccurrences(of: "raw/sources", with: "../outside-sources")
            .write(to: typePage, atomically: true, encoding: .utf8)
        let store = try openStore(url)
        #expect(store.resolve(Wikilink(target: "SRC-777-outside", label: nil, heading: nil)) == .missing)
        #expect(store.resolve(Wikilink(target: "SRC-777", label: nil, heading: nil)) == .missing)
        #expect(store.page(id: "SRC-777") == nil)
        #expect(store.folders().allSatisfy { store.pages(in: $0).allSatisfy { $0.id != "SRC-777" } })
    }
}

func setVersion(_ url: URL, _ line: String?) throws {
    let page = url.appending(path: "_system/metamodel/meta-metamodel.md")
    let text = try String(contentsOf: page, encoding: .utf8)
    let lines = text.components(separatedBy: "\n").map { $0.hasPrefix("version:") ? line : $0 }
    try lines.compactMap { $0 }.joined(separator: "\n").write(to: page, atomically: true, encoding: .utf8)
}

@Suite struct MetaTextTests {
    @Test func aHugeBodyIsScannedOnce() {
        let quotes = String(repeating: "> quote\n\n", count: 200_000)
        let body = "# Title\n\n" + quotes + "The definition.\nOn two lines.\n\nLater."
        #expect(MetaText.definition(of: body) == "The definition. On two lines.")
    }

    @Test func definitionSkipsListsQuotesAndComments() {
        let body = "# T\n\n<!-- c\n  still -->\n\n- a\n\n> q\n\nReal one.\n\nSecond."
        #expect(MetaText.definition(of: body) == "Real one.")
        #expect(MetaText.summary(of: "# T\n\n- a\n\nx") == "")
        #expect(MetaText.summary(of: "# T\n\nFirst para.\n\nSecond.") == "First para.")
        #expect(MetaText.withoutHeading("# T\n\nText") == "Text")
        #expect(MetaText.withoutHeading("Text\n\n## Sub") == "Text\n\n## Sub")
    }
}
