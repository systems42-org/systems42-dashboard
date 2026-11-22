import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

private let basic = Fixture.url("basic")

/// A fresh temp folder, removed by the OS later. Never inside `Tests/Fixtures/`.
private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "s42-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func copyOfBasic() throws -> URL {
    let url = try tempFolder().appending(path: "wiki-copy")
    try FileManager.default.copyItem(at: basic, to: url)
    return url
}

private func wikiWithConfig(_ yaml: String) throws -> WikiRoot {
    let url = try copyOfBasic()
    try yaml.write(to: url.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
    return WikiRoot(url: url)
}

@Test func completeWikiLacksNothing() {
    #expect(Preflight.missing(in: basic) == [])
}

@Test func everyMissingPartIsNamed() throws {
    #expect(Preflight.missing(in: try tempFolder()) == Preflight.required)
    #expect(Preflight.required == ["wiki", "raw", "_system/wiki.yaml", "_system/metamodel", "_system/anchors"])
}

@Test func fileWhereFolderBelongsCountsAsMissing() throws {
    let url = try copyOfBasic()
    try FileManager.default.removeItem(at: url.appending(path: "wiki"))
    try "x".write(to: url.appending(path: "wiki"), atomically: true, encoding: .utf8)
    #expect(Preflight.missing(in: url) == ["wiki"])
}

@Test func folderWhereFileBelongsCountsAsMissing() throws {
    let url = try copyOfBasic()
    try FileManager.default.removeItem(at: url.appending(path: "_system/wiki.yaml"))
    try FileManager.default.createDirectory(at: url.appending(path: "_system/wiki.yaml"), withIntermediateDirectories: false)
    #expect(Preflight.missing(in: url) == ["_system/wiki.yaml"])
}

@Test func openReturnsTheRoot() throws {
    #expect(try Preflight.open(basic) == WikiRoot(url: basic))
}

@Test func openThrowsWithTheMissingParts() throws {
    let url = try copyOfBasic()
    try FileManager.default.removeItem(at: url.appending(path: "_system/anchors"))
    #expect(throws: PreflightError.missing(["_system/anchors"])) {
        try Preflight.open(url)
    }
}

@Test func configReadsQuotedVersion() throws {
    let quoted = WikiConfig.load(try wikiWithConfig("dashboard_version: \"0.9.0\"\n"))
    #expect(quoted.dashboardVersion == "0.9.0")
    let word = WikiConfig.load(try wikiWithConfig("dashboard_version: local\n"))
    #expect(word.dashboardVersion == "local")
}

@Test func configReadsNameTaglineAndBrand() throws {
    let config = WikiConfig.load(try wikiWithConfig("system_name: Shop\ntagline: Sell more\nbrand: acme\n"))
    #expect(config.systemName == "Shop")
    #expect(config.tagline == "Sell more")
    #expect(config.brand == "acme")
    #expect(config.dashboardVersion == nil)
}

@Test func configOfBasicFixture() {
    #expect(WikiConfig.load(WikiRoot(url: basic)).systemName == "basic fixture")
}

@Test func configSurvivesBadYaml() throws {
    let config = WikiConfig.load(try wikiWithConfig(": : :\n"))
    #expect(config.systemName == "Requirements Wiki")
    #expect(config.brand == "systems42")
}

@Test func configFallsBackWhenFileIsMissingEmptyOrNotAMap() throws {
    let missing = try copyOfBasic()
    try FileManager.default.removeItem(at: missing.appending(path: "_system/wiki.yaml"))
    #expect(WikiConfig.load(WikiRoot(url: missing)).systemName == "Requirements Wiki")
    for yaml in ["", "- a\n- b\n", "system_name: \"  \"\nbrand: \"\"\n"] {
        let config = WikiConfig.load(try wikiWithConfig(yaml))
        #expect(config.systemName == "Requirements Wiki")
        #expect(config.brand == "systems42")
        #expect(config.tagline == "")
        #expect(config.dashboardVersion == nil)
    }
}

@Test func releaseNotice() {
    let text = ReleaseNotice.text(wikiNames: "0.9.0", appVersion: "0.13.0")
    #expect(text?.contains("0.9.0") == true)
    #expect(text?.contains("0.13.0") == true)
    #expect(ReleaseNotice.text(wikiNames: "0.13.0", appVersion: "0.13.0") == nil)
    #expect(ReleaseNotice.text(wikiNames: "local", appVersion: "0.13.0") == nil)
    #expect(ReleaseNotice.text(wikiNames: nil, appVersion: "0.13.0") == nil)
}

private func paths(_ urls: [URL]) -> [String] { urls.map(\.standardizedFileURL.path) }

private func folders(_ count: Int) throws -> [URL] {
    let parent = try tempFolder()
    return try (0..<count).map { index in
        let url = parent.appending(path: "w\(index)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

@Test func recentNewestFirstNoDuplicates() throws {
    var recent = RecentWikis(storage: try tempFolder())
    let w = try folders(2)
    recent.note(w[0]); recent.note(w[1]); recent.note(w[0])
    #expect(paths(recent.list()) == paths([w[0], w[1]]))
}

@Test func recentKeepsTen() throws {
    var recent = RecentWikis(storage: try tempFolder())
    let w = try folders(12)
    for url in w { recent.note(url) }
    #expect(paths(recent.list()) == paths(Array(w.reversed().prefix(10))))
}

@Test func recentDropsVanishedFolders() throws {
    var recent = RecentWikis(storage: try tempFolder())
    let w = try folders(2)
    recent.note(w[0]); recent.note(w[1])
    try FileManager.default.removeItem(at: w[1])
    #expect(paths(recent.list()) == paths([w[0]]))
}

@Test func recentSurvivesAcrossInstances() throws {
    let storage = try tempFolder().appending(path: "not-yet-there")
    var first = RecentWikis(storage: storage)
    let w = try folders(1)
    first.note(w[0])
    #expect(paths(RecentWikis(storage: storage).list()) == paths([w[0]]))
}

@Test func recentLivesOutsideTheWiki() throws {
    let wiki = try copyOfBasic()
    var recent = RecentWikis(storage: try tempFolder())
    assertUnchanged(wiki) { recent.note(wiki) }
}

@Test func entitlementsAreReadOnly() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/Systems42Dashboard/Systems42Dashboard.entitlements")
    let plist = try #require(
        PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
    )
    #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
    #expect(plist["com.apple.security.files.user-selected.read-only"] as? Bool == true)
    for key in ["com.apple.security.files.user-selected.read-write",
                "com.apple.security.network.client",
                "com.apple.security.network.server"] {
        #expect(plist[key] == nil, "\(key) must not be set")
    }
}

@Test func openingChangesNoFile() throws {
    let wiki = try copyOfBasic()
    assertUnchanged(wiki) {
        let root = try? Preflight.open(wiki)
        #expect(root != nil)
        if let root { _ = WikiConfig.load(root) }
    }
}
