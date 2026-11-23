import Foundation
import Testing
import Systems42TestSupport

/// `assertUnchanged` guards the "reads change no file" tests, so it must fail
/// when a file changes. `withKnownIssue` passes only if the body reports a failure.
@Suite struct AssertUnchangedTests {
    private func copy() throws -> URL { try Fixture.tempCopy("basic") }
    private let file = "wiki/domain-terms/DT-001-book.md"

    @Test func passesWhenNothingChanges() throws {
        let url = try copy()
        assertUnchanged(url) { _ = try? String(contentsOf: url.appending(path: file), encoding: .utf8) }
    }

    @Test func detectsAModifiedFile() throws {
        let url = try copy()
        let target = url.appending(path: file)
        let size = try Data(contentsOf: target).count
        withKnownIssue {
            assertUnchanged(url) {
                // Same size, other modification time.
                try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: target.path)
            }
        }
        withKnownIssue {
            assertUnchanged(url) {
                try? Data(count: size + 1).write(to: target)
            }
        }
    }

    @Test func detectsAnAddedFile() throws {
        let url = try copy()
        withKnownIssue {
            assertUnchanged(url) {
                try? "x".write(to: url.appending(path: "wiki/new.md"), atomically: true, encoding: .utf8)
            }
        }
    }

    @Test func detectsADeletedFile() throws {
        let url = try copy()
        withKnownIssue {
            assertUnchanged(url) {
                try? FileManager.default.removeItem(at: url.appending(path: file))
            }
        }
    }

    @Test func failsWhenTheFolderCannotBeListed() throws {
        let missing = try copy().appending(path: "not-there")
        withKnownIssue {
            assertUnchanged(missing) {}
        }
    }

    @Test func failsWhenAFolderInsideCannotBeListed() throws {
        let url = try copy()
        let locked = url.appending(path: "wiki/goals")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        withKnownIssue {
            assertUnchanged(url) {}
        }
    }
}
