import CoreServices
import Foundation
import os

/// Tells when files of an opened wiki change. It watches `wiki/`, `raw/sources/` and `_system/`
/// through FSEvents with file-level events, never the rest of the folder (not `.git/`).
///
/// Events are collected and delivered as one change after `debounce` without a new event, and
/// at the latest `maxWait` after the first one, so a long write run still shows progress.
/// `onChange` runs on a background queue. The URLs are under `root.url`, in the form the
/// caller knows, and cover only what the app reads: pages, `raw/sources/`, `_system/metamodel/`,
/// `_system/anchors/` and `_system/wiki.yaml`. A change that cannot be named (events were dropped,
/// the folder itself was moved or removed) arrives as the URL of the root.
///
/// The watcher only reads. It creates no file in the wiki and takes no lock on it.
/// `onChange` must not hold the object that owns the watcher, or that object is never freed.
public final class FileWatcher: Sendable {
    private let sink: Sink
    private let queue = DispatchQueue(label: "systems42.file-watcher", qos: .utility)
    /// The bit pattern of the `FSEventStreamRef`, 0 while no stream runs. A raw pointer is not
    /// `Sendable`, a number is, so the compiler needs no exception for it.
    private let stream = OSAllocatedUnfairLock<UInt>(initialState: 0)
    private let watched: [String]

    public init(
        root: WikiRoot, debounce: Duration = .milliseconds(300), maxWait: Duration = .milliseconds(1500),
        onChange: @escaping @Sendable ([URL]) -> Void
    ) {
        let real = Files.realPath(root.url) ?? root.url.path
        sink = Sink(rootReal: real, rootURL: root.url, debounce: debounce, maxWait: maxWait, onChange: onChange)
        watched = Self.watchPaths(under: real)
    }

    deinit { stop() }

    /// Starts watching. Does nothing when it already runs.
    public func start() {
        stream.withLock { running in
            guard running == 0 else { return }
            sink.reopen()
            let info = Unmanaged.passRetained(sink)
            var context = FSEventStreamContext(
                version: 0, info: info.toOpaque(), retain: nil,
                release: { pointer in if let pointer { Unmanaged<Sink>.fromOpaque(pointer).release() } },
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
            )
            guard let made = FSEventStreamCreate(
                nil, Self.callback, &context, watched as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags
            ) else {
                info.release()
                return
            }
            FSEventStreamSetDispatchQueue(made, queue)
            guard FSEventStreamStart(made) else {
                FSEventStreamInvalidate(made)
                FSEventStreamRelease(made)
                return
            }
            running = UInt(bitPattern: made)
        }
    }

    /// Stops watching. No call of `onChange` starts after it returns.
    public func stop() {
        sink.close()
        stream.withLock { running in
            guard running != 0, let made = FSEventStreamRef(bitPattern: running) else { return }
            running = 0
            FSEventStreamStop(made)
            FSEventStreamInvalidate(made)
            FSEventStreamRelease(made)
        }
    }

    /// The folders to watch: the three subtrees, each one or its nearest existing parent
    /// when it is not there yet (FSEvents does not report a path that does not exist).
    private static func watchPaths(under root: String) -> [String] {
        var result: [String] = []
        for relative in ["wiki", "raw/sources", "_system"] {
            var parts = relative.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                let path = ([root] + parts).joined(separator: "/")
                if FileManager.default.fileExists(atPath: path) {
                    if !result.contains(path) { result.append(path) }
                    break
                }
                parts.removeLast()
            }
        }
        return result.isEmpty ? [root] : result
    }

    /// The C callback. It captures nothing: the context pointer holds the `Sink`.
    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
        guard let info else { return }
        let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
        let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        var events: [(path: String, flags: UInt32)] = []
        for index in 0..<count { events.append((String(cString: paths[index]), eventFlags[index])) }
        sink.receive(events)
    }

    /// What the callback and the debounce share. Every field is immutable or behind the lock,
    /// so the compiler accepts it as `Sendable` without an exception. It knows no watcher,
    /// so a stream that still holds it never keeps the owner of the watcher alive.
    private final class Sink: Sendable {
        let rootReal: String
        let rootURL: URL
        let debounce: Duration
        let maxWait: Duration
        let onChange: @Sendable ([URL]) -> Void

        struct State {
            var pending: Set<String> = []
            var generation = 0
            var first: ContinuousClock.Instant?
            var open = true
        }
        let state = OSAllocatedUnfairLock(initialState: State())

        init(rootReal: String, rootURL: URL, debounce: Duration, maxWait: Duration, onChange: @escaping @Sendable ([URL]) -> Void) {
            self.rootReal = rootReal
            self.rootURL = rootURL
            self.debounce = debounce
            self.maxWait = maxWait
            self.onChange = onChange
        }

        func reopen() { state.withLock { $0.open = true } }

        func close() {
            state.withLock {
                $0.open = false
                $0.pending = []
                $0.first = nil
            }
        }

        private static let rescanFlags = UInt32(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
        )

        func receive(_ events: [(path: String, flags: UInt32)]) {
            var collected: Set<String> = []
            for event in events {
                if event.flags & Self.rescanFlags != 0 {
                    collected.insert(rootURL.path)
                } else if let relative = relevant(event.path) {
                    collected.insert(relative.isEmpty ? rootURL.path : rootURL.appending(path: relative).path)
                }
            }
            guard !collected.isEmpty else { return }
            let found = collected
            let now = ContinuousClock.now
            let step: (generation: Int, wait: Duration)? = state.withLock { state in
                guard state.open else { return nil }
                state.pending.formUnion(found)
                state.generation += 1
                let first = state.first ?? now
                state.first = first
                let left = maxWait - (now - first)
                return (state.generation, max(.zero, min(debounce, left)))
            }
            guard let step else { return }
            Task {
                try? await Task.sleep(for: step.wait)
                self.flush(generation: step.generation)
            }
        }

        /// Delivers what is pending, when this is the last event or the longest wait is over.
        private func flush(generation: Int) {
            let now = ContinuousClock.now
            let taken: Set<String>? = state.withLock { state in
                guard state.open, !state.pending.isEmpty, let first = state.first,
                      state.generation == generation || now - first >= maxWait else { return nil }
                defer { state.pending = []; state.first = nil }
                return state.pending
            }
            guard let taken else { return }
            onChange(taken.sorted().map { URL(fileURLWithPath: $0) })
        }

        /// The path below the root when the app reads it, "" for the root itself, else nil.
        func relevant(_ path: String) -> String? {
            guard path == rootReal || path.hasPrefix(rootReal + "/") else { return nil }
            let relative = String(path.dropFirst(rootReal.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relative.isEmpty { return "" }
            let parts = relative.split(separator: "/").map(String.init)
            for part in parts where part == ".git" { return nil }
            let name = parts[parts.count - 1]
            if name.hasPrefix(".") || name.hasPrefix("#") || name.hasSuffix("~") { return nil }
            let kept: Bool
            switch parts[0] {
            case "wiki": kept = true
            case "raw": kept = parts.count == 1 || parts[1] == "sources"
            case "_system": kept = parts.count == 1 || relative == "_system/wiki.yaml" || ["metamodel", "anchors"].contains(parts[1])
            default: kept = false
            }
            // A file the app does not read (an image, a lock file) is no change. A name without
            // an extension may be a folder, which can come or go with its pages.
            guard kept else { return nil }
            let ext = (name as NSString).pathExtension
            return ext.isEmpty || ext == "md" || ext == "yaml" ? relative : nil
        }
    }
}
