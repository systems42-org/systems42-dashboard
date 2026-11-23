import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor @Suite struct AboutTests {
    private func wiki(release: String?) throws -> (folder: URL, session: WikiSession) {
        let folder = try Fixture.tempCopy("basic")
        var yaml = "system_name: \"Library\"\n"
        if let release { yaml += "dashboard_version: \"\(release)\"\n" }
        try yaml.write(to: folder.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
        return (folder, WikiSession(root: try Preflight.open(folder)))
    }

    @Test func aboutNamesBothReleases() throws {
        let (folder, s) = try wiki(release: "0.9.0")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let model = AboutModel(appVersion: "0.13.0", session: s)
        #expect(model.appVersion == "0.13.0")
        #expect(model.wiki?.release == "0.9.0")
        #expect(model.wiki?.notice == ReleaseNotice.text(wikiNames: "0.9.0", appVersion: "0.13.0"))
        #expect(model.wiki?.notice?.contains("0.9.0") == true)
        #expect(model.wiki?.notice?.contains("0.13.0") == true)
    }

    @Test func noNoticeWhenTheReleasesAgreeOrNoneIsNamed() throws {
        for release in ["0.13.0", "local", nil] {
            let (folder, s) = try wiki(release: release)
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            let model = AboutModel(appVersion: "0.13.0", session: s)
            #expect(model.wiki?.notice == nil, "\(release ?? "nil")")
            #expect(model.wiki?.release == release)
        }
    }

    @Test func aboutHoldsMetamodelFolderAndRefreshTime() throws {
        let (folder, s) = try wiki(release: nil)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let model = AboutModel(appVersion: "1", session: s)
        let wiki = try #require(model.wiki)
        #expect(wiki.name == "Library")
        #expect(wiki.folder == s.root.url)
        #expect(wiki.refreshed == s.refreshedAt)
        #expect(wiki.supportedVersions == Metamodel.supportedVersions)
        #expect(!wiki.metamodel.isEmpty)
    }

    @Test func metamodelLineNamesTheVersionOrThatThereIsNone() {
        #expect(AboutModel.metamodelLine(.supported("0.1")) == "0.1")
        #expect(AboutModel.metamodelLine(.unsupported(found: "7", supported: ["0.1"])) == "7")
        #expect(AboutModel.metamodelLine(.missing(supported: ["0.1"])) == "names no version")
    }

    @Test func aboutWithoutAWikiHoldsTheAppOnly() {
        let model = AboutModel(appVersion: "0.13.0", session: nil)
        #expect(model.wiki == nil)
        #expect(model.appVersion == "0.13.0")
    }

    @Test func aReplacedWikiMovesTheRefreshTime() async throws {
        let (folder, s) = try wiki(release: nil)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let first = s.refreshedAt
        try await Task.sleep(for: .milliseconds(20))
        await s.refresh(changed: [])
        #expect(s.refreshedAt > first)
    }

    @Test func theHelpTextRenders() {
        #expect(HelpText.markdown.hasPrefix("# Help"))
        let page = renderPage(HelpText.markdown, resolve: { _ in .missing }, title: { _ in nil })
        #expect(page.blocks.count > 5)
        #expect(page.problems.isEmpty)
    }
}
