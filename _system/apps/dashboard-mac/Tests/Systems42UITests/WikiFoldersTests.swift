import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42UI

@Suite struct WikiFoldersTests {
    private let cwd = "/work/here"

    @Test func noArgumentGivesNothing() {
        #expect(WikiFolders.fromArguments([], currentDirectory: cwd) == nil)
    }

    @Test func aRelativePathIsResolvedAgainstTheCurrentDirectory() {
        #expect(WikiFolders.fromArguments(["wikis/a"], currentDirectory: cwd)?.path == "/work/here/wikis/a")
    }

    @Test func aPathAfterFlagsIsTaken() {
        let url = WikiFolders.fromArguments(["-NSDocumentRevisionsDebugMode", "YES", "-ApplePersistenceIgnoreState", "YES", "/w/x"], currentDirectory: cwd)
        #expect(url?.path == "/w/x")
        #expect(WikiFolders.fromArguments(["-flag", "-other", "value", "/w/x"], currentDirectory: cwd)?.path == "/w/x")
    }

    @Test func onlyFlagsGiveNothing() {
        #expect(WikiFolders.fromArguments(["-NSDocumentRevisionsDebugMode", "YES"], currentDirectory: cwd) == nil)
        #expect(WikiFolders.fromArguments(["-flag"], currentDirectory: cwd) == nil)
    }

    @Test func spellingsOfOneFolderGiveOneURL() {
        let plain = WikiFolders.fromArguments(["/w/x"], currentDirectory: cwd)
        #expect(WikiFolders.fromArguments(["/w/x/"], currentDirectory: cwd) == plain)
        #expect(WikiFolders.fromArguments(["/w/y/../x"], currentDirectory: cwd) == plain)
        #expect(WikiFolders.fromArguments(["../../w/x"], currentDirectory: cwd) == plain)
        #expect(WikiFolders.standardized(URL(fileURLWithPath: "/w/x")) == plain)
    }

    @Test func openedURLsBecomeWindowsOnlyForFolders() throws {
        let one = try Fixture.tempCopy("basic")
        let two = try Fixture.tempCopy("search")
        let file = one.appending(path: "_system/wiki.yaml")
        let web = try #require(URL(string: "https://example.org/x"))
        #expect(WikiFolders.fromOpened([one]) == [WikiFolders.standardized(one)])
        #expect(WikiFolders.fromOpened([file]).isEmpty)
        #expect(WikiFolders.fromOpened([web]).isEmpty)
        #expect(WikiFolders.fromOpened([one, file, two, web]) == [one, two].map(WikiFolders.standardized))
        #expect(WikiFolders.fromOpened([one, one.appending(path: "wiki/..")]) == [WikiFolders.standardized(one)])
    }

    @Test func recentLabelsAddTheParentOnlyForTwins() {
        let urls = ["/a/wiki", "/b/wiki", "/a/other"].map { URL(fileURLWithPath: $0) }
        #expect(WikiFolders.labels(for: urls) == ["wiki (a)", "wiki (b)", "other"])
    }
}
