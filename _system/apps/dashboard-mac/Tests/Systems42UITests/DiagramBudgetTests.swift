import AppKit
import Foundation
import Testing
import WebKit
@testable import Systems42UI

// Every wait is bounded by `limit`. Every test that sticks a web process kills it in a `defer`.

private let limit: Duration = .seconds(30)

@MainActor private func until(_ what: String, _ condition: () -> Bool) async {
    let started = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - started > limit { Issue.record("timed out waiting for \(what)"); return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// A page of its own budget, for tests that talk to a page. `end()` gives it back.
@MainActor final class OpenedPage {
    let budget: DiagramBudget
    let lease: DiagramBudget.Lease
    let page: DiagramPage

    private init(budget: DiagramBudget, lease: DiagramBudget.Lease, page: DiagramPage) {
        self.budget = budget
        self.lease = lease
        self.page = page
    }

    static func open(timeout: Duration = DiagramLimits.renderTimeout) async -> OpenedPage? {
        let budget = DiagramBudget()
        guard let recipe = await DiagramPage.recipe(timeout: timeout) else { return nil }
        let lease = budget.lease()
        let page = await budget.draw(lease, recipe: recipe) { page in await page.prepare() ? page : nil }
        guard let page = page ?? nil else { return nil }
        return OpenedPage(budget: budget, lease: lease, page: page)
    }

    func end() { budget.giveBack(lease) }
}

/// The process id of the web content process, when this macOS has the key. WebKit has no public call for it.
@MainActor func processID(of web: WKWebView) -> Int32? {
    guard web.responds(to: NSSelectorFromString("_webProcessIdentifier")) else { return nil }
    return (web.value(forKey: "_webProcessIdentifier") as? Int32).flatMap { $0 > 1 ? $0 : nil }
}

func isGone(_ pid: Int32) -> Bool {
    Darwin.kill(pid, 0) != 0 && errno == ESRCH
}

/// A chain of 400 boxes: the layout takes far longer than a millisecond.
let slowToDraw = DiagramContent(.mermaid("flowchart TB\n" + (0..<400).map { "  N\($0) --> N\($0 + 1)" }.joined(separator: "\n")))

private func flow(_ label: String) -> DiagramContent {
    DiagramContent(.mermaid("flowchart TB\n  A[\"\(label)\"] --> B[\"other\"]"))
}

private let forever = "for (;;) {}"

/// The process ids of the pages a budget has now.
@MainActor private func pids(of budget: DiagramBudget) -> [Int32] {
    budget.pages.compactMap { $0.webView.flatMap(processID) }
}

/// Loads a page for the lease and returns its process id. Nil on a macOS without the key.
@MainActor private func loaded(_ budget: DiagramBudget, _ lease: DiagramBudget.Lease, _ recipe: DiagramPage.Recipe) async -> Int32? {
    let pid = await budget.draw(lease, recipe: recipe) { page in await page.prepare() ? page.webView.flatMap(processID) : nil }
    return pid ?? nil
}

// MARK: A fake page for the state machine

/// Where fake pages are made: the recipe of a fake page, and the record of every page made.
@MainActor private final class FakeWorld {
    var made: [FakePage] = []
}

/// A page with no web view. The test drives its scripts. A script keeps the process busy until it answers,
/// also after the page was destroyed: releasing a web view does not stop a script. A stuck script answers
/// never, only a kill ends it. A ping answers only when no script runs.
@MainActor private final class FakePage: BudgetedPage {
    let meter: PageMeter
    private(set) var destroyed = false
    private(set) var killed = false
    private(set) var running = 0
    private(set) var stuck = false
    private var pings: [@MainActor @Sendable () -> Void] = []

    init(meter: PageMeter, recipe: FakeWorld) {
        self.meter = meter
        recipe.made.append(self)
    }

    func ping(_ done: @escaping @MainActor @Sendable () -> Void) { pings.append(done) }
    func destroy() { destroyed = true }

    /// The process runs a script, whatever the budget thinks.
    var reallyBusy: Bool { !killed && (stuck || running > 0) }
    var canAnswer: Bool { !killed && running > 0 && !stuck }

    func start() {
        guard !destroyed, meter.start() else { return }
        running += 1
    }

    func answer() {
        guard canAnswer else { return }
        running -= 1
        meter.answered()
    }

    func stick() {
        guard !killed, running > 0, !stuck else { return }
        stuck = true
        meter.noAnswer()
    }

    func answerPings() {
        guard running == 0, !stuck, !killed else { return }
        let waiting = pings
        pings = []
        for done in waiting { done() }
    }

    func kill() {
        guard !killed else { return }
        killed = true
        stuck = false
        running = 0
        meter.gone()
        let waiting = pings
        pings = []
        for done in waiting { done() }
    }
}

/// A small seeded generator, so a failing sequence can be run again.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor @Suite struct DiagramBudgetTests {
    @Test func theLimitsAreNamedAndTheAppHasOneBudget() {
        #expect(DiagramLimits.mostBusyPages == 4)
        #expect(DiagramLimits.mostPages == 8)
        #expect(DiagramBudget.shared.mostBusy == DiagramLimits.mostBusyPages)
        #expect(DiagramBudget.shared.mostPages == DiagramLimits.mostPages)
    }

    // MARK: The state machine, with fake pages

    @Test(arguments: [1, 7, 42, 2024, 31337])
    func randomOperationsKeepTheInvariants(seed: UInt64) {
        var random = SplitMix(state: seed)
        let world = FakeWorld()
        let budget = PageBudget<FakePage>(mostBusy: 2, mostPages: 4)
        let owners = 8
        var told = 0
        func newLease() -> PageBudget<FakePage>.Lease {
            let lease = budget.lease()
            lease.onEvicted = { told += 1 }
            return lease
        }
        var leases = (0..<owners).map { _ in newLease() }
        var grants: [PageBudget<FakePage>.Grant] = []
        var asked = 0
        var servedFromLine: [Int] = []
        var withdrawn = 0

        func check(_ step: Int, _ operation: String) {
            let alive = world.made.filter { !$0.destroyed }
            let counted = budget.pages
            let context = Comment(rawValue: "seed \(seed), step \(step), \(operation)")
            #expect(counted.count == alive.count, context)
            #expect(counted.allSatisfy { page in alive.contains { $0 === page } }, context)
            #expect(budget.busyCount <= budget.mostBusy, context)
            #expect(budget.pageCount <= budget.mostPages, context)
            #expect(world.made.filter(\.reallyBusy).count <= budget.mostBusy, context)
            #expect(servedFromLine == servedFromLine.sorted(), context)
        }

        func ask(_ owner: Int) {
            asked += 1
            let number = asked
            var queued = false
            queued = budget.ask(leases[owner], recipe: world) { grant in
                guard let grant else { withdrawn += 1; return }
                grants.append(grant)
                if queued { servedFromLine.append(number) }
            }
        }

        for step in 0..<400 {
            let owner = Int.random(in: 0..<owners, using: &random)
            let alive = world.made.filter { !$0.destroyed && !$0.killed }
            let processes = world.made.filter { !$0.killed }
            let operation = Int.random(in: 0..<14, using: &random)
            switch operation {
            case 0, 1, 2: ask(owner)
            case 3: grants.randomElement(using: &random)?.page.start()
            case 4: alive.randomElement(using: &random)?.start()
            case 5, 6: processes.filter(\.canAnswer).randomElement(using: &random)?.answer()
            case 7, 8:
                if let index = grants.indices.randomElement(using: &random) { budget.finish(grants.remove(at: index)) }
            case 9: processes.filter { $0.running > 0 }.randomElement(using: &random)?.stick()
            case 10: for page in world.made { page.answerPings() }
            case 11, 12:
                if Bool.random(using: &random) { budget.giveBack(leases[owner]) } else { leases[owner] = newLease() }
            default: processes.randomElement(using: &random)?.kill()
            }
            check(step, "operation \(operation)")
        }

        // Every stuck process killed, every script answered, every draw ended: nobody is left in line.
        for _ in 0..<50 where budget.waitingCount > 0 || !grants.isEmpty {
            for page in world.made where page.stuck { page.kill() }
            for page in world.made { while page.canAnswer { page.answer() } }
            for page in world.made { page.answerPings() }
            // Ending a draw may serve the line, and the new grants land in `grants`.
            let ending = grants
            grants = []
            for grant in ending { budget.finish(grant) }
            check(-1, "drain")
        }
        #expect(budget.waitingCount == 0, "no waiter starves")
        #expect(budget.busyCount == 0)
        // The sequence went through every path: waiting, withdrawing, evicting, abandoning.
        #expect(asked > 50 && !servedFromLine.isEmpty && withdrawn > 0 && budget.evictions > 0,
                "\(servedFromLine.count) \(withdrawn) \(budget.evictions)")
        #expect(told <= budget.evictions)
        #expect(world.made.contains { $0.killed } && world.made.contains { $0.stuck || $0.killed })
    }

    @Test func aGivenBackIdlePageIsDestroyedAndABusyOneStaysCounted() {
        let world = FakeWorld()
        let budget = PageBudget<FakePage>(mostBusy: 2, mostPages: 4)
        let idle = budget.lease(), busy = budget.lease()
        var granted: [PageBudget<FakePage>.Grant] = []
        budget.ask(idle, recipe: world) { if let grant = $0 { granted.append(grant) } }
        budget.ask(busy, recipe: world) { if let grant = $0 { granted.append(grant) } }
        for grant in granted { grant.page.start() }
        world.made[0].answer()
        budget.finish(granted[0])
        budget.giveBack(idle)
        #expect(world.made[0].destroyed && budget.pageCount == 1)
        // The busy page is abandoned: still counted, until its ping answers.
        budget.giveBack(busy)
        #expect(!world.made[1].destroyed && budget.busyCount == 1 && budget.abandonedCount == 1)
        world.made[1].answerPings()
        #expect(!world.made[1].destroyed, "no answer while its script runs")
        world.made[1].answer()
        world.made[1].answerPings()
        #expect(world.made[1].destroyed && budget.pageCount == 0)
    }

    // MARK: Real web views

    @Test func sixStuckOwnersNeverMakeMoreThanFourBusyProcesses() async throws {
        let budget = DiagramBudget(mostBusy: 4, mostPages: 8)
        var seen = Set<Int32>()
        defer { for pid in seen { Darwin.kill(pid, SIGKILL) } }
        let recipe = try #require(await DiagramPage.recipe())
        var mostBusySeen = 0, mostProcessesSeen = 0
        func sample() {
            seen.formUnion(pids(of: budget))
            mostBusySeen = max(mostBusySeen, budget.busyCount)
            mostProcessesSeen = max(mostProcessesSeen, seen.filter { !isGone($0) }.count)
        }
        var afterRound: [[Int]] = []
        for round in 0..<3 {
            let leases = (0..<6).map { _ in budget.lease() }
            var draws: [Task<Void, Never>] = []
            for lease in leases {
                draws.append(Task { _ = await budget.draw(lease, recipe: recipe) { page in await page.evaluate(forever, limit: .seconds(5)) } })
            }
            // The first round makes four pages that load and stick. Later rounds find no place at all.
            let started = ContinuousClock.now
            while !(budget.waitingCount == (round == 0 ? 2 : 6) && budget.pageCount == 4 && budget.pages.allSatisfy(\.isLoaded)) {
                sample()
                if ContinuousClock.now - started > limit { Issue.record("the draws did not start"); break }
                try await Task.sleep(for: .milliseconds(20))
            }
            for _ in 0..<15 {
                sample()
                try await Task.sleep(for: .milliseconds(20))
            }
            for lease in leases { budget.giveBack(lease) }
            for draw in draws { await draw.value }
            sample()
            #expect(budget.busyCount == 4 && budget.abandonedCount == 4 && budget.pageCount == 4 && budget.waitingCount == 0)
            afterRound.append([budget.busyCount, budget.pageCount, seen.count])
        }
        guard !seen.isEmpty else { Issue.record("no process ids on this macOS"); return }
        #expect(mostBusySeen <= 4)
        #expect(mostProcessesSeen <= 4, "only the four stuck pages ever had a process")
        #expect(afterRound.allSatisfy { $0 == afterRound[0] }, Comment(rawValue: "\(afterRound)"))
        #expect(seen.filter { !isGone($0) }.count == 4)
        // A killed process uncounts its page.
        for pid in seen { Darwin.kill(pid, SIGKILL) }
        await until("the killed pages to be uncounted") { budget.pageCount == 0 }
        #expect(budget.busyCount == 0)
    }

    @Test func anOwnerThatGoesAwayInMidDrawLeavesItsPageCounted() async throws {
        let budget = DiagramBudget(mostBusy: 1, mostPages: 2)
        var pids: [Int32] = []
        defer { for pid in pids { Darwin.kill(pid, SIGKILL) } }
        let recipe = try #require(await DiagramPage.recipe())
        var lease: DiagramBudget.Lease? = budget.lease()
        weak let gone = lease
        var found: Int32?
        if let owner = lease { found = await loaded(budget, owner, recipe) }
        let pid = try #require(found)
        pids.append(pid)
        let page = try #require(budget.pages.first)
        // The script holds the page, not the owner. Then the owner goes away without a word.
        let stuck = Task { _ = await page.evaluate(forever, limit: .seconds(2)) }
        await until("the page to draw") { budget.busyCount == 1 }
        lease = nil
        #expect(gone == nil)
        #expect(budget.pageCount == 1 && budget.busyCount == 1)
        // The script does not answer in time: the page is abandoned, and still counted.
        _ = await stuck.value
        #expect(budget.pageCount == 1 && budget.abandonedCount == 1)
        // A new diagram waits.
        let other = DiagramViewModel(budget: budget)
        let drawing = Task { await other.show(flow("NEXT"), dark: false) }
        await until("the wait") { other.state == .message(DiagramState.busy) }
        try await Task.sleep(for: .milliseconds(500))
        #expect(other.state == .message(DiagramState.busy) && budget.pageCount == 1)
        Darwin.kill(pid, SIGKILL)
        await drawing.value
        #expect(other.state == .drawn)
        other.close()
        #expect(budget.pageCount == 0)
    }

    @Test func theNinthIdleDiagramEvictsTheOneDrawnLongestAgo() async throws {
        let budget = DiagramBudget()
        let models = (0..<9).map { _ in DiagramViewModel(budget: budget) }
        defer { for model in models { model.close() } }
        for (n, model) in models.enumerated() {
            await model.show(flow("D\(n)"), dark: false)
            #expect(model.state == .drawn, "\(n)")
        }
        #expect(budget.pageCount == DiagramLimits.mostPages && budget.busyCount == 0)
        #expect(models[0].state == .message(DiagramState.evicted) && models[0].page == nil)
        #expect(models.dropFirst().allSatisfy { $0.state == .drawn && $0.page != nil })
        // It does not draw by itself.
        try await Task.sleep(for: .seconds(1))
        #expect(models[0].state == .message(DiagramState.evicted) && budget.pageCount == DiagramLimits.mostPages)
        // "Show diagram" draws it, and the one drawn longest ago now gives way.
        await models[0].show(flow("D0"), dark: false)
        #expect(models[0].state == .drawn)
        #expect(models[1].state == .message(DiagramState.evicted))
    }

    @Test func idlePagesDoNotBlockADraw() async throws {
        let budget = DiagramBudget()
        let models = (0..<DiagramLimits.mostBusyPages).map { _ in DiagramViewModel(budget: budget) }
        defer { for model in models { model.close() } }
        for model in models { await model.show(flow("IDLE"), dark: false) }
        #expect(models.allSatisfy { $0.state == .drawn })
        #expect(budget.busyCount == 0 && budget.pageCount == DiagramLimits.mostBusyPages)
        let recipe = try #require(await DiagramPage.recipe())
        let fifth = budget.lease()
        defer { budget.giveBack(fifth) }
        var waited = false
        let drawn = await budget.draw(fifth, recipe: recipe, waiting: { waited = true }) { page in await page.show(flow("FIFTH"), dark: false) }
        #expect(!waited && drawn == .drawn)
    }

    @Test func aLateAnswerUncountsAnAbandonedPageAndTheWaiterDraws() async throws {
        let budget = DiagramBudget(mostBusy: 1, mostPages: 2)
        var pids: [Int32] = []
        defer { for pid in pids { Darwin.kill(pid, SIGKILL) } }
        let recipe = try #require(await DiagramPage.recipe())
        let slow = budget.lease()
        if let pid = await loaded(budget, slow, recipe) { pids.append(pid) }
        let late = "const t = Date.now(); while (Date.now() - t < 6000) {} return 1;"
        let answer = await budget.draw(slow, recipe: recipe) { page in await page.evaluate(late, limit: .milliseconds(300)) }
        #expect(answer.flatMap { $0 } == nil, "the script did not answer in time")
        #expect(budget.abandonedCount == 1 && slow.page == nil)
        let waiter = DiagramViewModel(budget: budget)
        defer { waiter.close() }
        let drawing = Task { await waiter.show(flow("AFTER"), dark: false) }
        await until("the wait") { waiter.state == .message(DiagramState.busy) }
        await drawing.value
        #expect(waiter.state == .drawn)
        #expect(budget.abandonedCount == 0 && budget.pageCount == 1)
    }

    @Test func waitersAreServedInTheOrderTheyAsked() async throws {
        let budget = DiagramBudget(mostBusy: 1, mostPages: 8)
        var pids: [Int32] = []
        defer { for pid in pids { Darwin.kill(pid, SIGKILL) } }
        let recipe = try #require(await DiagramPage.recipe())
        let stuck = budget.lease()
        let pid = try #require(await loaded(budget, stuck, recipe))
        pids.append(pid)
        _ = await budget.draw(stuck, recipe: recipe) { page in await page.evaluate(forever, limit: .milliseconds(300)) }
        #expect(budget.abandonedCount == 1)
        var order: [String] = []
        var draws: [Task<Void, Never>] = []
        let names = ["B", "C", "D", "E"]
        let leases = names.map { _ in budget.lease() }
        defer { for lease in leases { budget.giveBack(lease) } }
        for (name, lease) in zip(names, leases) {
            let before = budget.waitingCount
            draws.append(Task { _ = await budget.draw(lease, recipe: recipe) { page in order.append(name); return await page.prepare() } })
            await until("\(name) in line") { budget.waitingCount == before + 1 }
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(order.isEmpty)
        Darwin.kill(pid, SIGKILL)
        for draw in draws { await draw.value }
        #expect(order == names)
        #expect(budget.waitingCount == 0)
    }

    @Test func aTimedOutDrawEndsItsProcessOnceItAnswers() async throws {
        let budget = DiagramBudget()
        var pids: [Int32] = []
        defer { for pid in pids { Darwin.kill(pid, SIGKILL) } }
        let recipe = try #require(await DiagramPage.recipe(timeout: .milliseconds(1)))
        for _ in 0..<3 {
            let lease = budget.lease()
            if let pid = await loaded(budget, lease, recipe) { pids.append(pid) }
            #expect(await budget.draw(lease, recipe: recipe) { page in await page.show(slowToDraw, dark: false) } == .timedOut)
            #expect(lease.page == nil)
        }
        guard pids.count == 3 else { Issue.record("no process ids on this macOS"); return }
        // The abandoned pages count until they answer, then they are destroyed and their processes end.
        await until("the budget to let go") { budget.pageCount == 0 }
        await until("the processes to end") { pids.allSatisfy(isGone) }
        #expect(pids.allSatisfy(isGone))
    }
}
