import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

private let terms = "domain-terms"

private func hostile() throws -> WikiStore { try openFixture("hostile") }

private func page(_ store: WikiStore, _ stem: String, in folder: String = terms) throws -> Page {
    try #require(store.page(ref(folder, stem)), "\(stem) did not load")
}

private func write(_ text: String, to url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
}

/// A temp copy of `hostile`, and a folder next to it that is outside the wiki.
private func hostileCopy() throws -> (url: URL, outside: URL, store: () throws -> WikiStore) {
    let url = try Fixture.tempCopy("hostile")
    let outside = url.deletingLastPathComponent().appending(path: "outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    return (url, outside, { try openStore(url) })
}

@Suite struct HostileVaultTests {
    @Test func theWholeFixtureLoads() throws {
        let store = try hostile()
        let stems = store.pages(in: terms).map(\.ref.stem)
        #expect(stems.count == 12)
        #expect(!stems.contains { $0.hasPrefix(".") })
        #expect(store.pages(in: "issues").count == 2)
        #expect(store.folders() == ["domain-terms", "issues"])
    }

    @Test func badYamlDoesNotThrow() throws {
        let store = try hostile()
        for stem in ["DT-900-unclosed-frontmatter", "DT-904-broken-yaml", "DT-905-list-frontmatter"] {
            let loaded = try page(store, stem)
            #expect(!loaded.problems.isEmpty, "\(stem)")
            #expect(loaded.title == stem, "\(stem)")
        }
        #expect(try page(store, "DT-900-unclosed-frontmatter").body.contains("never ends"))
    }

    @Test func wrongFieldTypesFallBack() throws {
        let loaded = try page(try hostile(), "DT-901-wrong-field-types")
        #expect(loaded.title == "DT-901-wrong-field-types")
        #expect(loaded.type == "")
        #expect(loaded.id == "DT-901")
        #expect(loaded.status == "draft")
        #expect(loaded.fields["title"] == .list(["a", "b"]))
        #expect(loaded.fields["parent"] == .text("7"))
        #expect(loaded.fields["related"] == .other)
        #expect(!loaded.problems.isEmpty)
    }

    @Test func noFrontmatterAtAll() throws {
        let loaded = try page(try hostile(), "DT-902-no-frontmatter")
        #expect(loaded.problems.count == 1)
        #expect(loaded.title == "DT-902-no-frontmatter")
        #expect(loaded.id == "DT-902-no-frontmatter")
        #expect(loaded.body.hasPrefix("# No frontmatter"))
    }

    @Test func emptyFile() throws {
        let loaded = try page(try hostile(), "DT-903-empty")
        #expect(!loaded.problems.isEmpty)
        #expect(loaded.body.isEmpty)
        #expect(loaded.title == "DT-903-empty")
    }

    @Test func aPageWithoutIdOrStatusUsesItsStem() throws {
        let loaded = try page(try hostile(), "DT-910-no-id")
        #expect(loaded.id == "DT-910-no-id")
        #expect(loaded.status == "")
        #expect(loaded.title == "No id, no status")
        #expect(loaded.problems.isEmpty)
    }

    @Test func anAliasBombIsCutOff() throws {
        let loaded = try page(try hostile(), "DT-907-alias-bomb")
        #expect(!loaded.problems.isEmpty)
        #expect(loaded.title == "Bomb")
        #expect(loaded.body.contains("Alias bomb"))
    }

    @Test func markupInATitleStaysText() throws {
        let loaded = try page(try hostile(), "DT-911-markup-title")
        #expect(loaded.title == "<script>alert(1)</script>")
    }

    @Test func duplicateIdsResolveToTheFirstPage() throws {
        let store = try hostile()
        #expect(store.page(id: "DT-908")?.ref.stem == "DT-908-duplicate-a")
    }

    @Test func linksToBrokenPagesAndSelfAreHandled() throws {
        let store = try hostile()
        let from = store.linksFrom(ref(terms, "DT-906-fine"))
        #expect(from["text"]?.map(\.stem) == ["DT-900-unclosed-frontmatter"])
        #expect(from["related"]?.map(\.stem) == ["DT-901-wrong-field-types"])
        // [[DT-906]] is a link to itself, [[SRC-001-ghost]] and [[raw/sources/x]] are sources.
        #expect(store.linksFrom(ref(terms, "DT-910-no-id")).values.flatMap { $0 }.map(\.stem) == ["DT-906-fine"])
        #expect(store.resolve(Wikilink(target: "Fine alias", label: nil, heading: nil)) == .page(ref(terms, "DT-906-fine")))
        #expect(store.resolve(Wikilink(target: "SRC-001-ghost", label: nil, heading: nil)) == .missing)
    }

    @Test func openIssuesLeaveOutClosedOnes() throws {
        let store = try hostile()
        #expect(store.openIssues(for: ref(terms, "DT-906-fine")).map(\.id) == ["ISS-900"])
        #expect(store.openIssues(for: ref(terms, "DT-902-no-frontmatter")).map(\.id) == ["ISS-900"])
        #expect(store.openIssues(for: ref(terms, "DT-900-unclosed-frontmatter")).isEmpty)
    }

    @Test func refCannotLeaveTheWiki() throws {
        let store = try hostile()
        let bad = [
            ref("../raw", "x"), ref("../raw/sources", ".gitkeep"), ref("/etc", "passwd"), ref("", "x"),
            ref(".", "x"), ref("..", "x"), ref(terms, ".."), ref(terms, "."), ref(terms, ""),
            ref(terms, "../../raw/sources/.gitkeep"), ref(terms, "a/b"), ref(terms, "a\\b"),
            ref(terms, "DT-906-fine\0"), ref("domain-terms/../issues", "ISS-900-open"),
        ]
        for r in bad {
            #expect(store.page(r) == nil, "\(r)")
            #expect(store.linksFrom(r).isEmpty)
            #expect(store.linksTo(r).isEmpty)
        }
        for folder in ["../raw", "/etc", "", ".", "..", "domain-terms/..", ".hidden"] {
            #expect(store.pages(in: folder).isEmpty, "\(folder)")
        }
    }

    @Test func storeChangesNoFile() throws {
        let copy = try Fixture.tempCopy("hostile")
        assertUnchanged(copy) {
            let store = try? openStore(copy)
            for folder in store?.folders() ?? [] {
                for page in store?.pages(in: folder) ?? [] { _ = store?.relations(of: page.ref) }
            }
        }
    }
}

@Suite struct HostileFilesTests {
    @Test func invalidUtf8LoadsWithAProblem() throws {
        let (url, _, store) = try hostileCopy()
        var bytes = Data("---\nid: DT-930\ntitle: Caf".utf8)
        bytes.append(contentsOf: [0xE9, 0x0A])
        bytes.append(Data("---\n\nbody ".utf8))
        bytes.append(contentsOf: [0xFF, 0xFE, 0x0A])
        try bytes.write(to: url.appending(path: "wiki/domain-terms/DT-930-latin1.md"))
        let store1 = try store()
        let loaded = try page(store1, "DT-930-latin1")
        #expect(!loaded.problems.isEmpty)
        #expect(loaded.title.hasPrefix("Caf"))
        #expect(store1.pages(in: terms).count == 13)
        #expect(try page(store1, "DT-906-fine").problems.isEmpty)
    }

    @Test func aFileOverFiveMegabytesIsNotLoaded() throws {
        let (url, _, store) = try hostileCopy()
        let limit = 5 * 1024 * 1024
        let big = "---\nid: DT-931\ntitle: Big\n---\n" + String(repeating: "x", count: limit)
        try write(big, to: url.appending(path: "wiki/domain-terms/DT-931-big.md"))
        let atLimit = "---\nid: DT-932\ntitle: Edge\n---\n" + String(repeating: "x", count: limit - 31)
        try write(atLimit, to: url.appending(path: "wiki/domain-terms/DT-932-edge.md"))
        let store1 = try store()
        let loaded = try page(store1, "DT-931-big")
        #expect(!loaded.problems.isEmpty)
        #expect(loaded.body.isEmpty)
        #expect(loaded.title == "DT-931-big")
        let edge = try page(store1, "DT-932-edge")
        #expect(edge.problems.isEmpty)
        #expect(edge.title == "Edge")
    }

    @Test func symlinkOutOfTheWikiIsNotFollowed() throws {
        let (url, outside, store) = try hostileCopy()
        try write("---\nid: DT-940\ntitle: Secret\n---\n", to: outside.appending(path: "secret.md"))
        let fm = FileManager.default
        let dir = url.appending(path: "wiki/domain-terms")
        try fm.createSymbolicLink(at: dir.appending(path: "DT-940-secret.md"), withDestinationURL: outside.appending(path: "secret.md"))
        // Into the same repository, but outside wiki/.
        try write("---\nid: DT-941\ntitle: Raw\n---\n", to: url.appending(path: "raw/sources/raw-page.md"))
        try fm.createSymbolicLink(at: dir.appending(path: "DT-941-raw.md"), withDestinationURL: url.appending(path: "raw/sources/raw-page.md"))
        // A whole folder.
        try fm.createSymbolicLink(at: url.appending(path: "wiki/escape"), withDestinationURL: outside)
        // A relative link that climbs out.
        try fm.createSymbolicLink(atPath: dir.appending(path: "DT-942-climb.md").path, withDestinationPath: "../../../outside/secret.md")
        let store1 = try store()
        for stem in ["DT-940-secret", "DT-941-raw", "DT-942-climb"] {
            #expect(store1.page(ref(terms, stem)) == nil, "\(stem)")
        }
        #expect(!store1.pages(in: terms).map(\.ref.stem).contains("DT-940-secret"))
        #expect(!store1.folders().contains("escape"))
        #expect(store1.pages(in: "escape").isEmpty)
        #expect(store1.page(id: "DT-940") == nil)
        #expect(store1.pages(in: terms).count == 12)
    }

    @Test func symlinkInsideTheWikiWorks() throws {
        let (url, _, store) = try hostileCopy()
        let fm = FileManager.default
        let dir = url.appending(path: "wiki/domain-terms")
        try fm.createSymbolicLink(at: dir.appending(path: "DT-950-twin.md"), withDestinationURL: dir.appending(path: "DT-906-fine.md"))
        try fm.createSymbolicLink(at: url.appending(path: "wiki/aliased"), withDestinationURL: url.appending(path: "wiki/issues"))
        let store1 = try store()
        #expect(try page(store1, "DT-950-twin").title == "Fine")
        #expect(store1.pages(in: "aliased").map(\.id) == ["ISS-900", "ISS-901"])
    }

    @Test func loopsBrokenLinksAndFoldersNamedLikePagesAreSkipped() throws {
        let (url, _, store) = try hostileCopy()
        let fm = FileManager.default
        let dir = url.appending(path: "wiki/domain-terms")
        try fm.createSymbolicLink(atPath: dir.appending(path: "DT-960-a.md").path, withDestinationPath: "DT-961-b.md")
        try fm.createSymbolicLink(atPath: dir.appending(path: "DT-961-b.md").path, withDestinationPath: "DT-960-a.md")
        try fm.createSymbolicLink(atPath: dir.appending(path: "DT-962-broken.md").path, withDestinationPath: "nowhere.md")
        try fm.createDirectory(at: dir.appending(path: "DT-963-folder.md"), withIntermediateDirectories: true)
        let store1 = try store()
        let stems = store1.pages(in: terms).map(\.ref.stem)
        #expect(stems.count == 12)
        for stem in ["DT-960-a", "DT-961-b", "DT-962-broken", "DT-963-folder"] {
            #expect(!stems.contains(stem))
            #expect(store1.page(ref(terms, stem)) == nil)
        }
    }

    @Test func anUnreadableFileIsAPageWithAProblem() throws {
        let (url, _, store) = try hostileCopy()
        let file = url.appending(path: "wiki/domain-terms/DT-906-fine.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let loaded = try page(try store(), "DT-906-fine")
        #expect(!loaded.problems.isEmpty)
    }

    @Test func anUnreadableFolderIsEmpty() throws {
        let (url, _, store) = try hostileCopy()
        let folder = url.appending(path: "wiki/issues")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let store1 = try store()
        #expect(store1.pages(in: "issues").isEmpty)
        #expect(store1.pages(in: terms).count == 12)
    }

    @Test func deeplyNestedFrontmatterIsRefused() throws {
        let (url, _, store) = try hostileCopy()
        let dir = url.appending(path: "wiki/domain-terms")
        let depth = 200_000
        try write("---\ntitle: Flow\nx: " + String(repeating: "[", count: depth) + "\n---\nbody\n", to: dir.appending(path: "DT-970-flow.md"))
        try write("---\ntitle: Flow map\nx: " + String(repeating: "{a: ", count: depth) + "\n---\nbody\n", to: dir.appending(path: "DT-971-map.md"))
        try write("---\ntitle: Block\nx:\n" + String(repeating: "- ", count: depth) + "a\n---\nbody\n", to: dir.appending(path: "DT-972-block.md"))
        try write("---\ntitle: Indent\nx:\n" + (0..<400).map { String(repeating: " ", count: $0 + 1) + "k\($0):" }.joined(separator: "\n") + "\n---\nbody\n", to: dir.appending(path: "DT-973-indent.md"))
        let store1 = try store()
        for stem in ["DT-970-flow", "DT-971-map", "DT-972-block", "DT-973-indent"] {
            let loaded = try page(store1, stem)
            #expect(!loaded.problems.isEmpty, "\(stem)")
            #expect(loaded.body == "body\n", "\(stem)")
        }
    }

    @Test func aBodyOfOpeningBracketsFinishes() throws {
        let (url, _, store) = try hostileCopy()
        try write("---\ntitle: Brackets\n---\n" + String(repeating: "[[", count: 400_000) + "x]]\n",
                  to: url.appending(path: "wiki/domain-terms/DT-980-brackets.md"))
        let store1 = try store()
        #expect(store1.linksFrom(ref(terms, "DT-980-brackets")).isEmpty)
        #expect(store1.openIssues(for: ref(terms, "DT-980-brackets")).isEmpty)
    }

    @Test func frontmatterEdgeShapes() throws {
        let (url, _, store) = try hostileCopy()
        let dir = url.appending(path: "wiki/domain-terms")
        try write("---\r\nid: DT-990\r\ntitle: Windows\r\n---\r\nbody\r\n", to: dir.appending(path: "DT-990-crlf.md"))
        try write("---\n---\nonly body\n", to: dir.appending(path: "DT-991-empty-fm.md"))
        try write("---\ntitle: Trailing\n---   \nbody", to: dir.appending(path: "DT-992-trailing.md"))
        try write("---\ntitle: \"quoted\"\nstatus: \nid: null\ntype: \"null\"\nparent: [[DT-906-fine]]\n---\n", to: dir.appending(path: "DT-993-nulls.md"))
        try write("---\ntitle: Dup\ntitle: Last\n---\n", to: dir.appending(path: "DT-994-dup-key.md"))
        try write("---\n? [a]\n: b\n---\n", to: dir.appending(path: "DT-995-complex-key.md"))
        try write("--- \ntitle: Space\n---\n", to: dir.appending(path: "DT-996-space.md"))
        let store1 = try store()
        let crlf = try page(store1, "DT-990-crlf")
        #expect(crlf.id == "DT-990" && crlf.title == "Windows" && crlf.body == "body\n")
        let emptyFM = try page(store1, "DT-991-empty-fm")
        #expect(emptyFM.body == "only body\n" && emptyFM.problems.isEmpty)
        #expect(try page(store1, "DT-992-trailing").title == "Trailing")
        let nulls = try page(store1, "DT-993-nulls")
        #expect(nulls.title == "quoted" && nulls.id == "DT-993-nulls" && nulls.status == "" && nulls.type == "null")
        #expect(nulls.fields["parent"] == .list(["DT-906-fine"]))
        let duplicate = try page(store1, "DT-994-dup-key")
        #expect(!duplicate.problems.isEmpty && duplicate.title == "DT-994-dup-key")
        _ = try page(store1, "DT-995-complex-key")
        #expect(try page(store1, "DT-996-space").title == "Space")
    }
}

@Suite struct HostileLayoutTests {
    @Test func aWikiFolderThatIsASymlinkOutOfTheRootShowsNoPages() throws {
        let (url, outside, _) = try hostileCopy()
        let fm = FileManager.default
        try fm.createDirectory(at: outside.appending(path: "domain-terms"), withIntermediateDirectories: true)
        try write("---\nid: DT-1\ntitle: Elsewhere\n---\n", to: outside.appending(path: "domain-terms/DT-1-elsewhere.md"))
        try fm.removeItem(at: url.appending(path: "wiki"))
        try fm.createSymbolicLink(at: url.appending(path: "wiki"), withDestinationURL: outside)
        let store = try openStore(url)
        #expect(store.folders().isEmpty)
        #expect(store.pages(in: "domain-terms").isEmpty)
        #expect(store.page(id: "DT-1") == nil)
    }

    @Test func rawSourcesThatIsASymlinkOutOfTheRootShowsNoSources() throws {
        let (url, outside, _) = try hostileCopy()
        let fm = FileManager.default
        try write("---\nid: SRC-9\ntitle: Elsewhere\n---\n", to: outside.appending(path: "SRC-9-elsewhere.md"))
        try fm.removeItem(at: url.appending(path: "raw/sources"))
        try fm.createSymbolicLink(at: url.appending(path: "raw/sources"), withDestinationURL: outside)
        let store = try openStore(url)
        #expect(store.resolve(Wikilink(target: "SRC-9", label: nil, heading: nil)) == .missing)
        #expect(store.pages(in: terms).count == 12)
    }

    @Test func aWikiSymlinkInsideTheRootStillWorks() throws {
        let (url, _, _) = try hostileCopy()
        let fm = FileManager.default
        try fm.moveItem(at: url.appending(path: "wiki"), to: url.appending(path: "real-wiki"))
        try fm.createSymbolicLink(at: url.appending(path: "wiki"), withDestinationURL: url.appending(path: "real-wiki"))
        let store = try openStore(url)
        #expect(store.pages(in: terms).count == 12)
        #expect(store.folders() == ["domain-terms", "issues"])
    }

    @Test func namesThatDifferOnlyInNormalizationAreOnePage() throws {
        let (url, _, _) = try hostileCopy()
        let dir = url.appending(path: "wiki/domain-terms")
        let composed = "DT-950-caf\u{E9}.md"
        let decomposed = "DT-950-cafe\u{301}.md"
        try write("---\nid: DT-950\ntitle: Cafe\n---\n", to: dir.appending(path: composed))
        var seen: [String: CachedPage] = [:]
        let pages = Files.pages(
            in: dir, folder: "domain-terms", inside: Files.realPath(dir) ?? "", cache: [:], seen: &seen,
            fileNames: [composed, decomposed]
        )
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Cafe")
        #expect(pages.first?.problems.count == 1)
    }

    @Test func foldersThatDifferOnlyInNormalizationAreOneFolder() throws {
        let (url, _, _) = try hostileCopy()
        let composed = "caf\u{E9}", decomposed = "cafe\u{301}"
        try FileManager.default.createDirectory(at: url.appending(path: "wiki/\(composed)"), withIntermediateDirectories: true)
        try write("---\nid: X-1\ntitle: X\n---\n", to: url.appending(path: "wiki/\(composed)/X-1-x.md"))
        var cache: [String: CachedPage] = [:]
        let snapshot = Snapshot.build(root: url, cache: &cache, folderNames: [composed, decomposed, "issues"])
        #expect(snapshot.folders.count == 2)
        #expect(snapshot.pagesByRef.count == 3)
    }

    @Test func harmlessFrontmatterIsNotTooDeep() throws {
        let (url, _, store) = try hostileCopy()
        let dir = url.appending(path: "wiki/domain-terms")
        let block = "---\ntitle: Block\nnote: |\n" + String(repeating: " ", count: 150) + "deep text\n"
            + String(repeating: " ", count: 150) + "- not a list [ ] { \n---\nbody\n"
        try write(block, to: dir.appending(path: "DT-960-block.md"))
        try write("---\ntitle: \"a [b\"\nx: don't [ stop {\ny: 'c {d'\nz: [\"[\", \"{\"]\n---\n", to: dir.appending(path: "DT-961-quotes.md"))
        var lines = "---\ntitle: Many\n"
        for i in 0..<300 { lines += "k\(i): a [b\n" }
        try write(lines + "---\n", to: dir.appending(path: "DT-962-many.md"))
        let store1 = try store()
        for stem in ["DT-960-block", "DT-961-quotes", "DT-962-many"] {
            let loaded = try page(store1, stem)
            #expect(loaded.problems.isEmpty, "\(stem) \(loaded.problems)")
        }
        #expect(try page(store1, "DT-961-quotes").title == "a [b")
    }
}
