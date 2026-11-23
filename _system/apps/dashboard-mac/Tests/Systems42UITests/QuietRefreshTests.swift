import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

/// A refresh that changes nothing a view shows changes nothing on screen: no dimming, no spinner, same value.
@MainActor private var held: [WikiSession] = []

@MainActor private func open(_ root: URL) async throws -> WikiSession {
    let session = await WikiSession.open(try Preflight.open(root))
    held.append(session)
    return session
}

private func edit(_ root: URL, _ path: String, _ change: (String) -> String) throws -> URL {
    let file = root.appending(path: path)
    try change(try String(contentsOf: file, encoding: .utf8)).write(to: file, atomically: true, encoding: .utf8)
    return file
}

/// Holds the builds after `arm()` until `release()`. A held build ends after 30 seconds.
private actor Hold {
    private var armed = false
    private var released = false
    private(set) var waiting = 0

    func arm() { armed = true }
    func release() { released = true }

    func pass() async {
        guard armed else { return }
        waiting += 1
        let end = ContinuousClock.now + .seconds(30)
        while !released && ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

@MainActor @Suite(.serialized) struct QuietRefreshTests {
    private func model(_ s: WikiSession, hold: Hold, delay: Duration) -> ProjectionsModel {
        ProjectionsModel(session: s, build: { store, metamodel, agreedOnly, revision in
            await hold.pass()
            return ProjectionData.build(store: store, metamodel: metamodel, agreedOnly: agreedOnly, revision: revision)
        }, updatingDelay: delay)
    }

    @Test func anUnrelatedChangeLeavesTheProjectionDataAlone() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let m = model(s, hold: Hold(), delay: .seconds(10))
        await m.load()
        let first = try #require(m.data)
        let file = try edit(root, "wiki/stakeholders/STK-002-reader.md") { $0 + "\nAnother sentence.\n" }
        await s.refresh(changed: [file])
        #expect(!m.isCurrent)
        var sawUpdating = false
        let loading = Task { await m.load() }
        while !loading.isCancelled && m.latest?.revision != s.revision {
            if m.isUpdating { sawUpdating = true }
            await Task.yield()
        }
        await loading.value
        #expect(!sawUpdating && !m.isUpdating)
        #expect(m.isCurrent)
        // The views keep the value they have. The snapshot for details is the new one.
        #expect(m.data?.revision == first.revision)
        #expect(m.latest?.revision == s.revision)
    }

    @Test func aChangeOfWhatIsShownReplacesTheData() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let m = model(s, hold: Hold(), delay: .seconds(10))
        await m.load()
        let file = try edit(root, "wiki/functional-requirements/FR-002-checkout.md") { $0.replacingOccurrences(of: "title: Checkout", with: "title: Check out") }
        await s.refresh(changed: [file])
        await m.load()
        #expect(m.data?.revision == s.revision)
    }

    @Test func aSlowRecomputeSaysUpdatingAndClears() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let hold = Hold()
        let m = model(s, hold: hold, delay: .milliseconds(50))
        await m.load()
        #expect(!m.isUpdating)
        await hold.arm()
        let file = try edit(root, "wiki/stakeholders/STK-002-reader.md") { $0 + "\nAnother sentence.\n" }
        await s.refresh(changed: [file])
        let loading = Task { await m.load() }
        let end = ContinuousClock.now + .seconds(30)
        while !m.isUpdating && ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.isUpdating)
        await hold.release()
        await loading.value
        #expect(!m.isUpdating)
    }

    @Test func searchKeepsItsResultsWhileItRebuilds() async throws {
        let root = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let s = try await open(root)
        let search = s.search
        await search.settle()
        search.query = "book"
        await search.settle()
        let before = search.quick.map(\.id)
        #expect(!before.isEmpty)
        let file = try edit(root, "wiki/stakeholders/STK-002-reader.md") { $0 + "\nAnother sentence.\n" }
        await s.refresh(changed: [file])
        search.followWiki()
        #expect(search.isIndexing && search.isRebuilding && !search.showsIndexing)
        #expect(search.quick.map(\.id) == before)
        await search.settle()
        #expect(!search.isIndexing && !search.isRebuilding)
        #expect(search.quick.map(\.id) == before)
    }
}
