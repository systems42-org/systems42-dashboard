import Foundation
import Testing
import Systems42TestSupport
@testable import Systems42Kit

@Suite struct ContainedPathTests {
    private func copy() throws -> (folder: URL, root: WikiRoot) {
        let url = try Fixture.tempCopy("basic")
        return (url, try Preflight.open(url))
    }

    @Test func aFolderInsideTheWikiIsFound() throws {
        let (folder, root) = try copy()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: folder.appending(path: "brand"), withIntermediateDirectories: true)
        let found = try #require(Preflight.contained("brand", in: root))
        #expect(found.lastPathComponent == "brand")
    }

    @Test func dotDotAndAbsolutePathsLeaveNothing() throws {
        let (folder, root) = try copy()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        #expect(Preflight.contained("../../x", in: root) == nil)
        #expect(Preflight.contained("..", in: root) == nil)
        #expect(Preflight.contained("/etc", in: root) == nil)
        #expect(Preflight.contained("", in: root) == nil)
    }

    @Test func aSymlinkThatLeadsOutIsRefused() throws {
        let (folder, root) = try copy()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let outside = folder.deletingLastPathComponent().appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "brand"), withDestinationURL: outside)
        #expect(Preflight.contained("brand", in: root) == nil)
    }

    @Test func aMissingPathGivesNil() throws {
        let (folder, root) = try copy()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        #expect(Preflight.contained("nope", in: root) == nil)
    }
}
