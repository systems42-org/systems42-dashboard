import Foundation
import Systems42Kit

/// What one refresh found.
private enum Refreshed: Sendable {
    case loaded(LoadedWiki)
    /// The folder is not a wiki any more: it was moved, removed or lost a part.
    case gone([String])
}

extension WikiSession {
    /// Whether the selected page no longer exists. The page column then says so.
    public var selectedPageWasRemoved: Bool {
        selectedPage.map { store.page($0) == nil } ?? false
    }

    /// Starts watching the wiki folder. Each change ends in one `refresh`. Does nothing when it runs already.
    public func startWatching() {
        guard watcher == nil else { return }
        // The callback holds the session weakly, so a closed window frees it.
        let started = FileWatcher(root: root) { [weak self] urls in
            Task { @MainActor in await self?.refresh(changed: urls) }
        }
        watcher = started
        started.start()
    }

    /// Stops watching. A refresh that is running ends normally.
    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// Reads the changed files again and shows the new state, in one `replace(with:)`. Selection, sort,
    /// filter and mode stay. The reading runs off the main thread.
    ///
    /// Two refreshes never run at once. A call during a refresh adds its files to one waiting set,
    /// and one more refresh reads that set after the running one. The call returns when the
    /// state it asked for is shown.
    ///
    /// An empty list means that something changed and nobody knows what: the whole folder is read again.
    public func refresh(changed: [URL]) async {
        changesWaiting.formUnion(changed.isEmpty ? [root.url] : changed)
        if let running = refreshing {
            await running.value
            return
        }
        let loop = Task { [weak self] in
            while let self, let batch = self.nextBatch() {
                await self.refreshOnce(batch)
            }
        }
        refreshing = loop
        await loop.value
    }

    /// The files waiting for a refresh, or nil (and no loop) when none wait.
    private func nextBatch() -> [URL]? {
        guard !changesWaiting.isEmpty else {
            refreshing = nil
            return nil
        }
        defer { changesWaiting = [] }
        return Array(changesWaiting)
    }

    private func refreshOnce(_ changed: [URL]) async {
        let root = self.root, previous = self.store
        if let hold = beforeReading { await hold(changed) }
        let result = await Task.detached(priority: .userInitiated) { () -> Refreshed in
            let missing = Preflight.missing(in: root.url)
            if !missing.isEmpty { return .gone(missing) }
            return .loaded(LoadedWiki(root: root, reusing: previous, changed: changed))
        }.value
        switch result {
        case .gone(let parts):
            missingParts = parts
        case .loaded(let loaded):
            missingParts = nil
            replace(with: loaded)
        }
    }
}
