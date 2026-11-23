import Foundation

/// How a page tells its budget about the scripts it runs. Only this file can make a meter, and a page needs
/// one to be made: so only a budget makes pages, and every page it makes is counted from the start.
@MainActor final class PageMeter {
    fileprivate var onStart: () -> Bool = { false }
    fileprivate var onAnswer: () -> Void = {}
    fileprivate var onNoAnswer: () -> Void = {}
    fileprivate var onGone: () -> Void = {}

    fileprivate init() {}

    /// Asks to run a script. False when the page may not: it was given up, or it is idle and no place is free.
    func start() -> Bool { onStart() }
    /// A script answered.
    func answered() { onAnswer() }
    /// A script did not answer in time. It may still run: the page stays counted.
    func noAnswer() { onNoAnswer() }
    /// The process of the page is gone.
    func gone() { onGone() }
}

/// A page a budget can make and count.
@MainActor protocol BudgetedPage: AnyObject {
    associatedtype Recipe
    init(meter: PageMeter, recipe: Recipe)
    /// Runs a trivial script. `done` is called once: when it answered, or when the process is gone.
    func ping(_ done: @escaping @MainActor @Sendable () -> Void)
    /// Lets the page and its web view go.
    func destroy()
}

/// The web views of diagrams, and the only place that makes them. WebKit has no public way to stop a running
/// script, and releasing a web view does not end a busy process. So the bound is on how many web views exist.
///
/// A page the budget made is in one of three states:
/// - drawing: a draw was granted or a script started, and has not answered,
/// - idle: the last draw answered,
/// - abandoned: its owner gave it back while it was drawing, or a script did not answer in time.
///
/// Drawing and abandoned pages are busy: at most `mostBusy`. All pages: at most `mostPages`. An idle page that is
/// given back is destroyed at once. An abandoned page is destroyed only when it answers a trivial script or its
/// process is gone. No timer ever uncounts a page. When a draw needs a new page and `mostPages` exist, the idle
/// page drawn longest ago is evicted. A draw that finds no place waits in line, and the line is served in order.
@MainActor class PageBudget<Page: BudgetedPage> {
    let mostBusy: Int
    let mostPages: Int

    /// The owner's handle on its page. The budget holds the page, the owner holds only this.
    @MainActor final class Lease {
        fileprivate weak var entry: Entry?
        /// Called when the budget evicted the idle page of this lease to make room.
        var onEvicted: (() -> Void)?
        fileprivate init() {}
        /// The page, while the lease has one.
        var page: Page? { entry?.page }
    }

    /// The right to one draw. It keeps the page busy until the draw ends.
    @MainActor final class Grant {
        fileprivate let entry: Entry
        fileprivate var open = true
        fileprivate init(_ entry: Entry) { self.entry = entry }
        var page: Page { entry.page }
    }

    @MainActor fileprivate final class Entry {
        let page: Page
        weak var lease: Lease?
        var granted = 0
        var running = 0
        var abandoned = false
        var lastDrawn: Int
        init(page: Page, lease: Lease, lastDrawn: Int) {
            self.page = page
            self.lease = lease
            self.lastDrawn = lastDrawn
        }
        var busy: Bool { abandoned || granted > 0 || running > 0 }
    }

    private struct Waiter {
        let lease: Lease
        let recipe: Page.Recipe
        let reply: (Grant?) -> Void
    }

    private var entries: [Entry] = []
    private var line: [Waiter] = []
    private var tick = 0
    private var serving = false

    init(mostBusy: Int, mostPages: Int) {
        self.mostBusy = mostBusy
        self.mostPages = max(mostPages, mostBusy)
    }

    func lease() -> Lease { Lease() }

    /// Every page that exists, idle ones included.
    var pageCount: Int { entries.count }
    /// The pages that are drawing or abandoned.
    var busyCount: Int { entries.filter(\.busy).count }
    var abandonedCount: Int { entries.filter(\.abandoned).count }
    var waitingCount: Int { line.count }
    /// How many idle pages were evicted to make room.
    private(set) var evictions = 0
    /// How many draws were asked for since the budget was made, granted or not. Tests count with it.
    private(set) var asks = 0
    /// The pages that exist, for tests.
    var pages: [Page] { entries.map(\.page) }

    /// Asks for one draw on the lease's page, or on a new page. `reply` gets the grant at once or later, in the
    /// order of asking, or nil when the lease is given back first. True when the request waits in line.
    @discardableResult
    func ask(_ lease: Lease, recipe: Page.Recipe, reply: @escaping (Grant?) -> Void) -> Bool {
        asks += 1
        let ownBusy = lease.entry?.busy == true
        if line.isEmpty || ownBusy, let grant = grant(lease, recipe) {
            reply(grant)
            return false
        }
        line.append(Waiter(lease: lease, recipe: recipe, reply: reply))
        return true
    }

    /// The draw of the grant is over.
    func finish(_ grant: Grant) {
        guard grant.open else { return }
        grant.open = false
        grant.entry.granted -= 1
        serve()
    }

    /// Runs one draw: waits for a grant, runs `work` on the page, ends the grant. `waiting` is called when the
    /// draw has to wait in line. Nil when the lease was given back before its turn.
    func draw<T>(_ lease: Lease, recipe: Page.Recipe, waiting: () -> Void = {}, _ work: @MainActor (Page) async -> T) async -> T? {
        let grant: Grant? = await withCheckedContinuation { continuation in
            if ask(lease, recipe: recipe, reply: { continuation.resume(returning: $0) }) { waiting() }
        }
        guard let grant else { return nil }
        let result = await work(grant.page)
        finish(grant)
        return result
    }

    /// The owner lets go: its place in line, and its page. An idle page is destroyed, a busy one is abandoned.
    func giveBack(_ lease: Lease) {
        let withdrawn = line.filter { $0.lease === lease }
        line.removeAll { $0.lease === lease }
        if let entry = lease.entry {
            unlink(entry)
            if entry.busy { abandon(entry) } else { destroy(entry) }
        }
        for waiter in withdrawn { waiter.reply(nil) }
        serve()
    }

    // MARK: State changes

    private func grant(_ lease: Lease, _ recipe: Page.Recipe) -> Grant? {
        if let entry = lease.entry {
            guard entry.busy || busyCount < mostBusy else { return nil }
            entry.granted += 1
            return Grant(entry)
        }
        guard busyCount < mostBusy else { return nil }
        if entries.count >= mostPages {
            let idle = entries.filter { !$0.busy }
            guard let oldest = idle.min(by: { $0.lastDrawn < $1.lastDrawn }) else { return nil }
            evict(oldest)
        }
        return make(for: lease, recipe)
    }

    /// The single place where a page is made.
    private func make(for lease: Lease, _ recipe: Page.Recipe) -> Grant {
        let meter = PageMeter()
        tick += 1
        let entry = Entry(page: Page(meter: meter, recipe: recipe), lease: lease, lastDrawn: tick)
        meter.onStart = { [weak self, weak entry] in
            guard let self, let entry, self.holds(entry), !entry.abandoned else { return false }
            if !entry.busy, busyCount >= mostBusy || !line.isEmpty { return false }
            entry.running += 1
            return true
        }
        meter.onAnswer = { [weak self, weak entry] in
            guard let self, let entry, self.holds(entry) else { return }
            entry.running = max(0, entry.running - 1)
            tick += 1
            entry.lastDrawn = tick
            serve()
        }
        meter.onNoAnswer = { [weak self, weak entry] in
            guard let self, let entry, self.holds(entry) else { return }
            abandon(entry)
        }
        meter.onGone = { [weak self, weak entry] in
            guard let self, let entry else { return }
            destroy(entry)
        }
        entry.granted = 1
        entries.append(entry)
        lease.entry = entry
        return Grant(entry)
    }

    private func holds(_ entry: Entry) -> Bool { entries.contains { $0 === entry } }

    private func unlink(_ entry: Entry) {
        if entry.lease?.entry === entry { entry.lease?.entry = nil }
        entry.lease = nil
    }

    /// The page stays counted until it answers a trivial script or its process is gone. The ping holds the
    /// budget: a page that never answers keeps its place for as long as the app runs.
    private func abandon(_ entry: Entry) {
        unlink(entry)
        guard !entry.abandoned else { return }
        entry.abandoned = true
        entry.page.ping { [self, entry] in destroy(entry) }
    }

    private func evict(_ entry: Entry) {
        evictions += 1
        let lease = entry.lease
        destroy(entry)
        lease?.onEvicted?()
    }

    private func destroy(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0 === entry }) else { return }
        entries.remove(at: index)
        unlink(entry)
        entry.page.destroy()
        serve()
    }

    /// Hands out grants to the line, in order, while there is room.
    private func serve() {
        guard !serving else { return }
        serving = true
        defer { serving = false }
        while let first = line.first, let grant = grant(first.lease, first.recipe) {
            line.removeFirst()
            first.reply(grant)
        }
    }
}

/// The diagram web views of the whole app, in every window.
@MainActor final class DiagramBudget: PageBudget<DiagramPage> {
    static let shared = DiagramBudget()

    override init(mostBusy: Int = DiagramLimits.mostBusyPages, mostPages: Int = DiagramLimits.mostPages) {
        super.init(mostBusy: mostBusy, mostPages: mostPages)
    }
}
