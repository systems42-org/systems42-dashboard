import Foundation
import Observation
import os
import Systems42Kit

/// The filters of the full result list (FR-009), in the order they show.
///
/// Open debt (CON-006): the list is code, not metamodel. The core's filters know exactly these four,
/// and the field names `priority` and `tags` are the ones the dashboard indexes (search.go).
/// The metamodel does not say which fields are worth a filter. Labels and values come from the wiki.
enum SearchFilterFields {
    struct Field: Sendable {
        let name: String
        /// The key of the field in `SearchEntry.fields`, nil for the type and the status, which are entry properties.
        let entryKey: String?
    }

    static let all = [
        Field(name: "type", entryKey: nil), Field(name: "status", entryKey: nil),
        Field(name: "priority", entryKey: "priority"), Field(name: "tag", entryKey: "tags"),
    ]
}

enum SearchLimits {
    /// The most suggestions under the field.
    static let mostSuggestions = 8
}

extension SearchFilter {
    /// The filter without one of its fields: how a field's counts are taken (search.html `apply()`).
    func without(_ field: String) -> SearchFilter {
        var f = self
        switch field {
        case "type": f.types = []
        case "status": f.statuses = []
        case "priority": f.priorities = []
        case "tag": f.tags = []
        default: break
        }
        return f
    }

    func isOn(_ field: String) -> Bool {
        switch field {
        case "type": !types.isEmpty
        case "status": !statuses.isEmpty
        case "priority": !priorities.isEmpty
        case "tag": !tags.isEmpty
        default: false
        }
    }
}

/// The running steps of a model, so a newer step cancels the older one and a model that goes away
/// cancels all of them. The tasks only hold the model weakly: a cancel just saves work.
final class SearchWork: Sendable {
    enum Slot { case build, quick, full, mark }
    private struct Slots: Sendable { var build, quick, full, mark: Task<Void, Never>? }
    private let slots = OSAllocatedUnfairLock(initialState: Slots())

    func start(_ slot: Slot, _ task: Task<Void, Never>) {
        let old = slots.withLock { s -> Task<Void, Never>? in
            switch slot {
            case .build: defer { s.build = task }; return s.build
            case .quick: defer { s.quick = task }; return s.quick
            case .full: defer { s.full = task }; return s.full
            case .mark: defer { s.mark = task }; return s.mark
            }
        }
        old?.cancel()
    }

    /// Cancels the step in the slot and leaves it empty.
    func cancel(_ slot: Slot) {
        let old = slots.withLock { s -> Task<Void, Never>? in
            switch slot {
            case .build: defer { s.build = nil }; return s.build
            case .quick: defer { s.quick = nil }; return s.quick
            case .full: defer { s.full = nil }; return s.full
            case .mark: defer { s.mark = nil }; return s.mark
            }
        }
        old?.cancel()
    }

    /// Empties the slot of a step that has finished.
    func finish(_ slot: Slot) {
        slots.withLock { s in
            switch slot {
            case .build: s.build = nil
            case .quick: s.quick = nil
            case .full: s.full = nil
            case .mark: s.mark = nil
            }
        }
    }

    var running: Task<Void, Never>? {
        slots.withLock { $0.build ?? $0.quick ?? $0.full ?? $0.mark }
    }

    deinit {
        slots.withLock { s in
            for task in [s.build, s.quick, s.full, s.mark] { task?.cancel() }
        }
    }
}

/// A value a filter offers, with how many of the shown hits have it.
public struct SearchOption: Identifiable, Sendable, Equatable {
    /// Lower case, as the filter takes it.
    public let value: String
    /// As the wiki writes it.
    public let label: String
    public let count: Int
    public var id: String { value }
}

/// One run of the search: what to ask and how much to return.
struct SearchJob: Sendable {
    let index: SearchIndex
    let query: String
    let filter: SearchFilter
    /// The full list with passages, related pages and facets, or only the suggestions.
    let full: Bool
}

struct SearchOutcome: Sendable {
    var hits: [SearchHit] = []
    var related: [SearchHit] = []
    var facets: [(field: String, values: [(String, Int)])] = []
}

/// The two slow steps of the search. The model runs them off the main thread, and a test swaps
/// them for gated ones to pin the order in which results arrive.
struct SearchBackend: Sendable {
    var build: @Sendable (WikiStore, Metamodel) async -> SearchIndex
    var run: @Sendable (SearchJob) async -> SearchOutcome
    /// The marks of a page text: text, query, words the passage marked.
    var mark: @Sendable (String, String, [String]) async -> PageMarks

    /// Runs `work` on a detached task that is cancelled with the calling task.
    private static func detached<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let task = Task.detached(priority: .userInitiated) { work() }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    static let live = SearchBackend(
        build: { store, metamodel in await detached { SearchIndex(store: store, metamodel: metamodel) } },
        run: { job in await detached { perform(job) } },
        mark: { text, query, passage in await detached { PageMarks.compute(text: text, query: query, matchedInPassage: passage) } }
    )

    static func perform(_ job: SearchJob) -> SearchOutcome {
        guard job.full else {
            let found = search(job.query, in: job.index, filter: job.filter, withPassages: false, withRelated: false)
            return SearchOutcome(hits: Array(found.prefix(SearchLimits.mostSuggestions)))
        }
        let found = search(job.query, in: job.index, filter: job.filter, withPassages: true)
        let hits = found.filter { $0.group == .hit }
        return SearchOutcome(hits: hits, related: found.filter { $0.group == .related }, facets: facets(of: hits, for: job))
    }

    /// How many hits have each value of each filter field, the most frequent value first.
    /// Like the web dashboard (search.html `apply()`), a field's counts are taken over the hits that
    /// pass all the other filters, not its own: choosing one type leaves the other types their counts.
    /// Hits are looked up by page, not by id: a wiki does not promise unique ids.
    private static func facets(of hits: [SearchHit], for job: SearchJob) -> [(field: String, values: [(String, Int)])] {
        var byRef: [PageRef: SearchEntry] = [:]
        for entry in job.index.entries {
            if let ref = entry.ref, byRef[ref] == nil { byRef[ref] = entry }
        }
        var out: [(field: String, values: [(String, Int)])] = []
        for field in SearchFilterFields.all {
            var base = hits
            if job.filter.isOn(field.name) {
                if Task.isCancelled { return out }
                base = search(job.query, in: job.index, filter: job.filter.without(field.name), withPassages: false, withRelated: false)
            }
            var counts: [String: Int] = [:]
            for hit in base {
                let values: [String]
                switch field.name {
                case "type": values = [hit.type]
                case "status": values = hit.status.isEmpty ? [] : [hit.status.lowercased()]
                default: values = hit.ref.flatMap { byRef[$0] }.flatMap { entry in field.entryKey.flatMap { entry.fields[$0] } } ?? []
                }
                for value in Set(values) { counts[value, default: 0] += 1 }
            }
            let sorted = counts.sorted { a, b in
                a.value != b.value ? a.value > b.value : a.key.utf8.lexicographicallyPrecedes(b.key.utf8)
            }
            out.append((field: field.name, values: sorted.map { ($0.key, $0.value) }))
        }
        return out
    }
}

/// The search of one wiki: the text field, its suggestions and the full result list.
///
/// The index is built off the main thread. Until it is ready `quick` and `hits` stay empty and
/// `isIndexing` is true. A result for an older query or an older wiki is dropped. The session owns
/// this model and the model holds the session weakly, as the other models do.
@MainActor @Observable public final class SearchModel {
    public var query = "" { didSet { queryChanged(from: oldValue) } }
    public var filter = SearchFilter() { didSet { filterChanged(from: oldValue) } }

    /// The suggestions for the typed text: at most 8, without passages, without related pages.
    public private(set) var quick: [SearchHit] = []
    /// The full list for the committed query, with passages.
    public private(set) var hits: [SearchHit] = []
    /// Pages one link from the strong hits (FR-008).
    public private(set) var related: [SearchHit] = []
    /// For each filter field, the values of the shown hits with their counts.
    public private(set) var facets: [(field: String, values: [(String, Int)])] = []
    /// True until the index of the current wiki is ready.
    public private(set) var isIndexing = true
    public private(set) var suggestionsOpen = false
    /// The suggestion the arrow keys are on.
    public private(set) var highlighted: Int?
    /// Counts up when something asks the field to take the keyboard focus.
    public private(set) var focusRequests = 0
    /// Counts up when the keyboard focus should move to the result list, after Return shows it.
    public private(set) var listFocusRequests = 0

    @ObservationIgnored weak var session: WikiSession?
    @ObservationIgnored private let backend: SearchBackend
    @ObservationIgnored private var index: SearchIndex?
    @ObservationIgnored private var indexRevision = -1
    /// What `hits` is for, nil when no result list is shown.
    @ObservationIgnored private var shown: SearchRequest?
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private let work = SearchWork()
    /// How many results arrived, kept or dropped. A test waits on it, see `finished(atLeast:)`.
    @ObservationIgnored private(set) var arrivals = 0
    @ObservationIgnored private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    /// The marks of the page opened from a result, and what they are for.
    private var markState: (ref: PageRef, revision: Int, marks: PageMarks)?
    @ObservationIgnored private var markToken = 0
    @ObservationIgnored private var buildToken = 0
    @ObservationIgnored private var quickToken = 0
    @ObservationIgnored private var hitsToken = 0

    public convenience init(session: WikiSession) {
        self.init(session: session, backend: .live)
    }

    init(session: WikiSession, backend: SearchBackend) {
        self.session = session
        self.backend = backend
        startBuild()
    }

    // MARK: Index

    private func startBuild() {
        guard let session else { return }
        let revision = session.revision, store = session.store, metamodel = session.metamodel
        index = nil
        indexRevision = revision
        isIndexing = true
        clearResults()
        buildToken += 1
        let token = buildToken
        work.start(.build, Task { [weak self, backend] in
            let built = await backend.build(store, metamodel)
            self?.finishBuild(built, token: token)
        })
    }

    private func finishBuild(_ built: SearchIndex, token: Int) {
        arrived()
        guard token == buildToken else { return }
        work.finish(.build)
        guard session?.revision == indexRevision else {
            startBuild()
            return
        }
        index = built
        isIndexing = false
        runQuick()
        runFull()
    }

    /// Builds the index again when the session holds a newer wiki.
    private func ensureCurrent() {
        if let session, session.revision != indexRevision { startBuild() }
    }

    /// Call when the session's revision changed. The views do it on `onChange`.
    public func followWiki() {
        ensureCurrent()
    }

    private func clearResults() {
        quickToken += 1
        hitsToken += 1
        work.cancel(.quick)
        work.cancel(.full)
        quick = []
        hits = []
        related = []
        facets = []
        highlighted = nil
    }

    /// Waits until the index is built and no search is running. Tests use it, nothing sleeps.
    public func settle() async {
        while let task = work.running { await task.value }
    }

    // MARK: Searching

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func queryChanged(from old: String) {
        guard query != old else { return }
        ensureCurrent()
        if !restoring {
            suggestionsOpen = !Self.trimmed(query).isEmpty
            highlighted = nil
        }
        runQuick()
    }

    private func filterChanged(from old: SearchFilter) {
        guard filter != old, let shown, shown.filter != filter else { return }
        let request = SearchRequest(query: shown.query, filter: filter)
        self.shown = request
        session?.refineSearch(request)
        ensureCurrent()
        runFull()
    }

    private func runQuick() {
        quickToken += 1
        let token = quickToken
        work.cancel(.quick)
        guard !Self.trimmed(query).isEmpty, let index else {
            quick = []
            return
        }
        let job = SearchJob(index: index, query: query, filter: SearchFilter(), full: false)
        let revision = indexRevision
        work.start(.quick, Task { [weak self, backend] in
            let outcome = await backend.run(job)
            self?.finishQuick(outcome, token: token, revision: revision)
        })
    }

    private func finishQuick(_ outcome: SearchOutcome, token: Int, revision: Int) {
        arrived()
        guard token == quickToken else { return }
        work.finish(.quick)
        guard revision == session?.revision else {
            ensureCurrent()
            return
        }
        quick = outcome.hits
        if let h = highlighted, !quick.indices.contains(h) { highlighted = nil }
    }

    private func runFull() {
        hitsToken += 1
        let token = hitsToken
        work.cancel(.full)
        guard let shown, let index else {
            hits = []
            related = []
            facets = []
            return
        }
        let job = SearchJob(index: index, query: shown.query, filter: shown.filter, full: true)
        let revision = indexRevision
        work.start(.full, Task { [weak self, backend] in
            let outcome = await backend.run(job)
            self?.finishFull(outcome, token: token, revision: revision)
        })
    }

    private func finishFull(_ outcome: SearchOutcome, token: Int, revision: Int) {
        arrived()
        guard token == hitsToken else { return }
        work.finish(.full)
        guard revision == session?.revision else {
            ensureCurrent()
            return
        }
        hits = outcome.hits
        related = outcome.related
        facets = outcome.facets
    }

    private func arrived() {
        arrivals += 1
        let ready = arrivalWaiters.filter { $0.count <= arrivals }
        arrivalWaiters.removeAll { $0.count <= arrivals }
        for waiter in ready { waiter.continuation.resume() }
    }

    /// Returns once at least `count` results have arrived, kept or dropped. For tests that hold a
    /// run and need to know it came back and was judged.
    func finished(atLeast count: Int) async {
        if arrivals >= count { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
    }

    // MARK: Actions

    /// Return: shows the full list in the list column. An empty query does nothing.
    public func commit() {
        guard !Self.trimmed(query).isEmpty else { return }
        ensureCurrent()
        let request = SearchRequest(query: query, filter: filter)
        shown = request
        suggestionsOpen = false
        highlighted = nil
        session?.showSearch(request)
        runFull()
        listFocusRequests += 1
    }

    /// Return in the field: opens the page the arrow keys are on, else shows the full list.
    public func submit() {
        if suggestionsOpen, let h = highlighted, quick.indices.contains(h) {
            open(quick[h])
        } else {
            commit()
        }
    }

    /// Opens the page of a hit. With `keepingResults` the list stays and Back returns to it.
    public func open(_ hit: SearchHit, keepingResults: Bool = false) {
        guard let ref = hit.ref, let session else { return }
        suggestionsOpen = false
        highlighted = nil
        prepareMarks(of: ref, query: keepingResults ? (shown?.query ?? query) : query, passage: hit.passage?.marked ?? [])
        if keepingResults { session.selectResult(ref) } else { session.open(.page(ref)) }
    }

    /// Up and down in the suggestions. It wraps at both ends. False, and nothing done, while no
    /// suggestions are open, so the key goes on to the system.
    @discardableResult
    public func moveHighlight(by step: Int) -> Bool {
        let count = quick.count
        guard suggestionsOpen, count > 0 else { return false }
        if let h = highlighted {
            highlighted = ((h + step) % count + count) % count
        } else {
            highlighted = step > 0 ? 0 : count - 1
        }
        return true
    }

    /// Escape: closes the suggestions.
    public func dismissSuggestions() {
        suggestionsOpen = false
        highlighted = nil
    }

    /// Cmd-K and Cmd-F: asks the field to take the focus.
    public func focusField() {
        focusRequests += 1
        suggestionsOpen = !Self.trimmed(query).isEmpty && !quick.isEmpty
    }

    /// Makes the model show what the session shows: call it when the session's `shownSearch` changed,
    /// after Back, Forward or a click in the sidebar.
    public func followSession() {
        let target = session?.shownSearch
        guard target != shown else { return }
        shown = target
        if let target {
            restoring = true
            query = target.query
            filter = target.filter
            restoring = false
        }
        runFull()
    }

    // MARK: Filters

    /// The values a filter offers, with the counts among the shown hits. Empty for an unknown field or before the index is ready.
    public func options(for field: String) -> [SearchOption] {
        guard let index, let session else { return [] }
        let counts = Dictionary(
            (facets.first { $0.field == field }?.values ?? []).map { ($0.0.lowercased(), $0.1) },
            uniquingKeysWith: { a, _ in a })
        func make(_ value: String, _ label: String) -> SearchOption {
            SearchOption(value: value, label: label, count: counts[value] ?? 0)
        }
        switch field {
        case "type":
            var labels: [String] = []
            let present = Set(index.entries.map(\.type))
            for label in session.metamodel.types.map(\.label) where present.contains(label) && !labels.contains(label) { labels.append(label) }
            for label in present.sorted() where !labels.contains(label) { labels.append(label) }
            return labels.map { make($0.lowercased(), $0) }
        case "status": return index.filterOptions.statuses.map { make($0.value, $0.label) }
        case "priority": return index.filterOptions.priorities.map { make($0.value, $0.label) }
        case "tag": return index.filterOptions.tags.map { make($0.value, $0.label) }
        default: return []
        }
    }

    public func isSelected(field: String, value: String) -> Bool {
        set(of: field, in: filter)?.contains(value.lowercased()) == true
    }

    /// Adds the value to the filter, or removes it when it is there.
    public func toggle(field: String, value: String) {
        var next = filter
        guard var chosen = set(of: field, in: next) else { return }
        let low = value.lowercased()
        if !chosen.insert(low).inserted { chosen.remove(low) }
        assign(chosen, to: field, in: &next)
        filter = next
    }

    public func clearFilter() { filter = SearchFilter() }

    public var hasFilter: Bool { filter != SearchFilter() }

    private func set(of field: String, in f: SearchFilter) -> Set<String>? {
        switch field {
        case "type": f.types
        case "status": f.statuses
        case "priority": f.priorities
        case "tag": f.tags
        default: nil
        }
    }

    private func assign(_ values: Set<String>, to field: String, in f: inout SearchFilter) {
        switch field {
        case "type": f.types = values
        case "status": f.statuses = values
        case "priority": f.priorities = values
        case "tag": f.tags = values
        default: break
        }
    }

    // MARK: Marks in the opened page

    /// Starts finding the words to mark in a page. The page shows unmarked until they arrive. A newer
    /// call, or a newer wiki, drops an older result.
    private func prepareMarks(of ref: PageRef, query: String, passage: [String]) {
        markToken += 1
        let token = markToken
        markState = nil
        guard let session, let page = session.store.page(ref), !PageMarks.words(of: query).isEmpty else {
            work.cancel(.mark)
            return
        }
        let revision = session.revision, text = page.body
        work.start(.mark, Task { [weak self, backend] in
            let marks = await backend.mark(text, query, passage)
            self?.finishMarks(marks, ref: ref, revision: revision, token: token)
        })
    }

    private func finishMarks(_ marks: PageMarks, ref: PageRef, revision: Int, token: Int) {
        arrived()
        guard token == markToken else { return }
        work.finish(.mark)
        guard revision == session?.revision else { return }
        markState = (ref, revision, marks)
    }

    /// The words to mark in the selected page when it was opened from a suggestion or a result.
    /// Nothing for any other page, and nothing while the marks are still being found.
    public func pageMarks(for ref: PageRef) -> PageMarks {
        guard let markState, markState.ref == ref, markState.revision == session?.revision,
              session?.selectedPage == ref else { return .none }
        return markState.marks
    }
}
