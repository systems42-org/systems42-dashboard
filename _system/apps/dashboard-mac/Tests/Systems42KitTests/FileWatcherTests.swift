import Foundation
import Testing
import os
import Systems42TestSupport
@testable import Systems42Kit

/// Real FSEvents. Every wait has a bound of 30 seconds, because CI is slower than a laptop.
/// The tests check that a change arrives once, not how fast. One test records the time.
private final class Calls: Sendable {
    private let batches = OSAllocatedUnfairLock<[[URL]]>(initialState: [])

    func add(_ urls: [URL]) { batches.withLock { $0.append(urls) } }
    var all: [[URL]] { batches.withLock { $0 } }
    var names: Set<String> { Set(all.flatMap { $0 }.map(\.lastPathComponent)) }
}

private let limit = Duration.seconds(30)

/// Polls until `condition` holds or 30 seconds are over. Returns whether it held.
private func wait(_ condition: @Sendable () -> Bool) async -> Bool {
    let end = ContinuousClock.now + limit
    while ContinuousClock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

private struct Watched {
    let folder: URL
    let root: URL
    let watcher: FileWatcher
    let calls: Calls

    func remove() { watcher.stop(); try? FileManager.default.removeItem(at: folder) }
}

private func watch(debounce: Duration = .milliseconds(300)) throws -> Watched {
    let root = try Fixture.tempCopy("basic")
    let calls = Calls()
    let watcher = FileWatcher(root: try Preflight.open(root), debounce: debounce) { calls.add($0) }
    watcher.start()
    return Watched(folder: root.deletingLastPathComponent(), root: root, watcher: watcher, calls: calls)
}

private let term = "wiki/domain-terms/DT-001-book.md"

@Suite(.serialized) struct FileWatcherTests {
    @Test func editIsSeen() async throws {
        let w = try watch()
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(300))
        let file = w.root.appending(path: "wiki/functional-requirements/FR-002-checkout.md")
        // An editor writes a temp file and renames it over the page.
        let text = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "title: Checkout", with: "title: Check out")
        try text.write(to: file, atomically: true, encoding: .utf8)
        #expect(await wait { w.calls.names.contains("FR-002-checkout.md") })
        try await Task.sleep(for: .seconds(2))
        #expect(w.calls.all.filter { $0.contains { $0.lastPathComponent == "FR-002-checkout.md" } }.count == 1)
        #expect(w.calls.all.flatMap { $0 }.allSatisfy { $0.path.hasPrefix(w.root.path + "/") })
    }

    @Test func burstIsOneChange() async throws {
        // A slow machine may take longer than 300 ms for 50 writes, which would split the burst.
        let w = try watch(debounce: .seconds(1))
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(300))
        for number in 0..<50 {
            try "x".write(to: w.root.appending(path: "wiki/domain-terms/DT-9\(number)-burst.md"), atomically: false, encoding: .utf8)
        }
        #expect(await wait { !w.calls.all.isEmpty })
        try await Task.sleep(for: .seconds(2))
        #expect(w.calls.all.count == 1)
        // FSEvents may add the folder itself or a file from the fixture copy to the batch.
        #expect(w.calls.names.filter { $0.hasSuffix("-burst.md") }.count == 50)
    }

    @Test func stopEndsCallbacks() async throws {
        let w = try watch()
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(300))
        w.watcher.stop()
        try "x".write(to: w.root.appending(path: "wiki/domain-terms/DT-900-late.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(1.5))
        #expect(w.calls.all.isEmpty)
    }

    @Test func stopDropsWhatWaits() async throws {
        let w = try watch(debounce: .seconds(1))
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(300))
        try "x".write(to: w.root.appending(path: "wiki/domain-terms/DT-900-late.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))
        w.watcher.stop()
        try await Task.sleep(for: .seconds(2))
        #expect(w.calls.all.isEmpty)
    }

    @Test func startAgainAfterStop() async throws {
        let w = try watch()
        defer { w.remove() }
        w.watcher.stop()
        w.watcher.start()
        w.watcher.start()
        try await Task.sleep(for: .milliseconds(300))
        try "x".write(to: w.root.appending(path: "wiki/domain-terms/DT-901-again.md"), atomically: true, encoding: .utf8)
        #expect(await wait { w.calls.names.contains("DT-901-again.md") })
    }

    @Test func watchingChangesNoFile() async throws {
        let w = try watch()
        defer { w.remove() }
        try await assertUnchangedAsync(w.root) {
            try await Task.sleep(for: .seconds(1))
            w.watcher.stop()
            w.watcher.start()
            try await Task.sleep(for: .milliseconds(500))
            w.watcher.stop()
        }
        #expect(w.calls.all.isEmpty)
    }

    @Test func whatTheAppDoesNotReadIsNoChange() async throws {
        let w = try watch()
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(300))
        let fm = FileManager.default
        try fm.createDirectory(at: w.root.appending(path: ".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: w.root.appending(path: "_system/scripts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: w.root.appending(path: "other"), withIntermediateDirectories: true)
        for path in [".git/index.md", "other/x.md", "raw/inbox.md", "_system/scripts/run.md", "wiki/domain-terms/.hidden.md",
                     "wiki/domain-terms/DT-1~", "wiki/domain-terms/pic.png"] {
            try "x".write(to: w.root.appending(path: path), atomically: false, encoding: .utf8)
        }
        try await Task.sleep(for: .seconds(2))
        #expect(w.calls.all.isEmpty)
        try "x".write(to: w.root.appending(path: "raw/sources/SRC-900-a.md"), atomically: false, encoding: .utf8)
        try "x".write(to: w.root.appending(path: "_system/metamodel/new.md"), atomically: false, encoding: .utf8)
        try "x".write(to: w.root.appending(path: "_system/wiki.yaml"), atomically: false, encoding: .utf8)
        #expect(await wait { w.calls.names.isSuperset(of: ["SRC-900-a.md", "new.md", "wiki.yaml"]) })
    }

    @Test func aSymlinkOutOfTheWikiIsNotFollowed() async throws {
        let w = try watch()
        defer { w.remove() }
        let outside = w.folder.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: w.root.appending(path: "wiki/escape"), withDestinationURL: outside)
        #expect(await wait { w.calls.names.contains("escape") })
        let before = w.calls.all.count
        try await Task.sleep(for: .milliseconds(300))
        try "x".write(to: outside.appending(path: "away.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(2))
        #expect(!w.calls.names.contains("away.md"))
        #expect(w.calls.all.count == before)
    }

    @Test func removingTheRootIsReported() async throws {
        let w = try watch()
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.removeItem(at: w.root)
        #expect(await wait { !w.calls.all.isEmpty })
        #expect(await wait { w.calls.all.flatMap { $0 }.contains { $0.path == w.root.path } })
    }

    /// Records how long a saved page takes to arrive. The product aim is 2 seconds (FR-065) on a normal
    /// machine. The test fails only above the 30 second bound.
    @Test func timeFromWriteToChange() async throws {
        let w = try watch()
        defer { w.remove() }
        try await Task.sleep(for: .milliseconds(500))
        let start = ContinuousClock.now
        try "x".write(to: w.root.appending(path: term), atomically: true, encoding: .utf8)
        let arrived = await wait { w.calls.names.contains("DT-001-book.md") }
        let took = ContinuousClock.now - start
        print("write to change: \(took)")
        #expect(arrived)
        #expect(took < limit)
    }

    // MARK: The sink, driven without FSEvents

    private func sink(_ calls: Calls, debounce: Duration = .milliseconds(100)) -> (FileWatcher.Sink, URL) {
        let root = URL(fileURLWithPath: "/tmp/s42-sink-root")
        return (FileWatcher.Sink(rootReal: root.path, rootURL: root, debounce: debounce, maxWait: .seconds(1), onChange: { calls.add($0) }), root)
    }

    @Test func eventsOutsideTheRootAndInGitAreDropped() async throws {
        let calls = Calls()
        let (sink, root) = sink(calls)
        sink.receive([
            (path: "/tmp/elsewhere/wiki/x.md", flags: 0),
            // As long as the root, so cutting off the root's length leaves a path that looks fine.
            (path: "/" + String(repeating: "x", count: root.path.count - 1) + "/wiki/domain-terms/DT-9-out.md", flags: 0),
            (path: "/tmp/s42-sink-root-other/wiki/x.md", flags: 0),
            (path: root.path + "/.git/x.md", flags: 0),
            (path: root.path + "/wiki/.git/x.md", flags: 0),
        ])
        try await Task.sleep(for: .milliseconds(600))
        #expect(calls.all.isEmpty)
        sink.receive([(path: root.path + "/wiki/domain-terms/DT-1-a.md", flags: 0)])
        #expect(await wait { calls.names == ["DT-1-a.md"] })
    }

    @Test func aClosedSinkDeliversNothing() async throws {
        let calls = Calls()
        let (sink, root) = sink(calls)
        sink.receive([(path: root.path + "/wiki/domain-terms/DT-1-a.md", flags: 0)])
        sink.close()
        try await Task.sleep(for: .milliseconds(600))
        #expect(calls.all.isEmpty, "what waited was delivered after close")
        sink.receive([(path: root.path + "/wiki/domain-terms/DT-2-b.md", flags: 0)])
        try await Task.sleep(for: .milliseconds(600))
        #expect(calls.all.isEmpty, "an event after close was delivered")
        sink.reopen()
        sink.receive([(path: root.path + "/wiki/domain-terms/DT-3-c.md", flags: 0)])
        #expect(await wait { calls.names == ["DT-3-c.md"] })
    }
}
