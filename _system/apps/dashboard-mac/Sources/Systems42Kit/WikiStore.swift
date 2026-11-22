import Foundation

/// What a wikilink points at.
public enum LinkTarget: Equatable, Sendable {
    case page(PageRef)
    /// A provenance record in `raw/sources/`, by its stem.
    case source(String)
    /// A method anchor in `_system/anchors/`, by its name.
    case anchor(String)
    /// A page of `_system/metamodel/`, by its name.
    case metamodel(String)
    case missing
}

/// The links of a page the way the dashboard's detail page shows them.
///
/// `WikiStore.linksFrom` and `linksTo` are the raw view: every link, grouped by
/// the field it stands in. This is the folded view, each list sorted by stem:
/// - `traced` holds the pages of the trace panel of an architecture or requirement
///   page: drivers, realizes, decisions, supersession, uses, hosts, applies-to,
///   steps and their reverse. The panel lists them, so the link lists leave them out.
/// - `linksTo` holds the other pages this page links to.
/// - `linkedFrom` holds the other pages that link here, without those already in
///   `linksTo`: a page on both sides is listed under `linksTo` only.
public struct PageRelations: Equatable, Sendable {
    public let linksTo: [PageRef]
    public let linkedFrom: [PageRef]
    public let traced: [PageRef]
}

/// Reads the wiki folder: pages, links and backlinks. It never writes a file and
/// no call throws. A file it cannot read becomes a page with `problems`.
///
/// It reads a snapshot of the folder the first time a question needs one and keeps
/// it until `reload`. Parsed pages are kept by file modification time and size,
/// so a rebuild after `reload` parses only the files that changed.
///
/// A link resolves by full stem, then by id, then by alias. A link follows the
/// dashboard in what it counts: the wikilinks of every frontmatter field at any
/// depth and of the body, without links to `raw/` or `SRC-` records and without
/// self links. Unlike the dashboard it also resolves by id and alias. A link
/// written without quotes in YAML (`parent: [[FR-001]]`) is a list in a list, so
/// YAML drops the brackets and the link does not count, as in the dashboard.
public final class WikiStore: @unchecked Sendable {
    private let root: WikiRoot

    private let lock = NSLock()
    // `lock` guards `cache` and `snapshot`. A build holds it from start to end, so two
    // threads asking at once build once. A snapshot is immutable and shared freely.
    private var cache: [String: CachedPage] = [:]
    private var snapshot: Snapshot?

    public init(root: WikiRoot) {
        self.root = root
    }

    /// The sub-folders of `wiki/`, sorted. Hidden folders and folders that lead out of the wiki are left out.
    public func folders() -> [String] {
        current().folders
    }

    /// The pages of one folder in file name order. Empty for an unknown folder.
    public func pages(in folder: String) -> [Page] {
        current().pagesByFolder[folder] ?? []
    }

    /// The page at `ref`, nil when it does not exist or `ref` is not a plain folder and stem.
    public func page(_ ref: PageRef) -> Page? {
        ref.isSafe ? current().pagesByRef[ref] : nil
    }

    /// The first page whose id (or, without an id, stem) is `id`.
    public func page(id: String) -> Page? {
        let snapshot = current()
        return snapshot.names.byId[id].flatMap { snapshot.pagesByRef[$0] }
    }

    public func resolve(_ link: Wikilink) -> LinkTarget {
        current().names.resolve(link)
    }

    /// The pages `ref` links to, by the field the link stands in, or "text" for the body.
    /// Each list is in the order of the links, without duplicates and without `ref` itself.
    public func linksFrom(_ ref: PageRef) -> [String: [PageRef]] {
        ref.isSafe ? current().outgoing[ref] ?? [:] : [:]
    }

    /// The pages that link to `ref`, by the field of the linking page (or "text"),
    /// each list sorted by stem.
    public func linksTo(_ ref: PageRef) -> [String: [PageRef]] {
        ref.isSafe ? current().incoming[ref] ?? [:] : [:]
    }

    /// The links of `ref` as the dashboard's detail page shows them. See `PageRelations`.
    /// `traced` holds only pages that exist, as the dashboard lists no others.
    public func relations(of ref: PageRef) -> PageRelations {
        let snapshot = current()
        guard ref.isSafe, snapshot.pagesByRef[ref] != nil else { return PageRelations(linksTo: [], linkedFrom: [], traced: []) }
        let shown = snapshot.traceTargets(of: ref)
        let out = Set((snapshot.outgoing[ref] ?? [:]).values.joined()).subtracting(shown)
        let into = Set((snapshot.incoming[ref] ?? [:]).values.joined())
            .subtracting(shown).subtracting(out).subtracting([ref])
        return PageRelations(linksTo: Snapshot.sorted(out), linkedFrom: Snapshot.sorted(into), traced: Snapshot.sorted(shown))
    }

    /// The open issues (status neither `resolved` nor `wontfix`) whose frontmatter or body
    /// link to `ref`, in id order.
    public func openIssues(for ref: PageRef) -> [Page] {
        let snapshot = current()
        guard ref.isSafe else { return [] }
        return (snapshot.pagesByFolder["issues"] ?? [])
            .filter { issue in
                let status = issue.status.lowercased()
                return status != "resolved" && status != "wontfix"
                    && (snapshot.outgoing[issue.ref] ?? [:]).values.contains { $0.contains(ref) }
            }
            .sorted { $0.id < $1.id }
    }

    /// Forget what was read. With `nil` everything is read again. With files, those
    /// files are read again and the rest keeps its parsed pages. Either way the
    /// next question builds a new snapshot, so added and removed files show up.
    public func reload(changed: [URL]?) {
        lock.withLock {
            snapshot = nil
            guard let changed else { cache = [:]; return }
            let paths = Set(changed.map(\.path))
            let real = Set(changed.compactMap(Files.realPath))
            cache = cache.filter { key, _ in !paths.contains(key) && !(Files.realPath(path: key).map(real.contains) ?? false) }
        }
    }

    private func current() -> Snapshot {
        lock.withLock {
            if let snapshot { return snapshot }
            let built = Snapshot.build(root: root.url, cache: &cache)
            snapshot = built
            return built
        }
    }
}

struct CachedPage {
    let modified: Date?
    let size: Int
    let page: Page
}

/// The most a page file may hold. A bigger file is a page with a problem, unread.
let largestPageFile = 5 * 1024 * 1024

/// How a link resolves, independent of any file access.
struct Names: Sendable {
    var byStem: [String: PageRef] = [:]
    var byId: [String: PageRef] = [:]
    var byAlias: [String: PageRef] = [:]
    var sources: [String: String] = [:]
    var anchors: [String: String] = [:]
    var metamodel: [String: String] = [:]

    func resolve(_ link: Wikilink) -> LinkTarget {
        let name = link.name
        if link.target.hasPrefix("raw/") || name.hasPrefix("SRC-") {
            if let source = sources[name] { return .source(source) }
        } else if let found = byStem[name] ?? byId[name] ?? byAlias[name] {
            return .page(found)
        }
        let key = name.lowercased()
        if let anchor = anchors[key] { return .anchor(anchor) }
        if let term = metamodel[key] { return .metamodel(term) }
        return .missing
    }
}

/// Everything read from the folder at one time. Never changes after it is built.
final class Snapshot: Sendable {
    let folders: [String]
    let pagesByFolder: [String: [Page]]
    let pagesByRef: [PageRef: Page]
    let names: Names
    let outgoing: [PageRef: [String: [PageRef]]]
    let incoming: [PageRef: [String: [PageRef]]]

    private init(
        folders: [String], pagesByFolder: [String: [Page]], names: Names,
        outgoing: [PageRef: [String: [PageRef]]], incoming: [PageRef: [String: [PageRef]]]
    ) {
        self.folders = folders
        self.pagesByFolder = pagesByFolder
        self.pagesByRef = Dictionary(uniqueKeysWithValues: pagesByFolder.values.joined().map { ($0.ref, $0) })
        self.names = names
        self.outgoing = outgoing
        self.incoming = incoming
    }

    static func sorted(_ refs: some Sequence<PageRef>) -> [PageRef] {
        refs.sorted { ($0.stem, $0.folder) < ($1.stem, $1.folder) }
    }

    static func build(root: URL, cache: inout [String: CachedPage]) -> Snapshot {
        var seen: [String: CachedPage] = [:]
        defer { cache = seen }

        var folders: [String] = []
        var pagesByFolder: [String: [Page]] = [:]
        let wiki = root.appending(path: "wiki")
        if let wikiReal = Files.realPath(wiki) {
            for name in Files.names(in: wiki) where !name.hasPrefix(".") {
                let url = wiki.appending(path: name)
                guard Files.isFolder(url, inside: wikiReal) else { continue }
                folders.append(name)
                pagesByFolder[name] = Files.pages(in: url, folder: name, inside: wikiReal, cache: cache, seen: &seen)
            }
        }
        let all = folders.flatMap { pagesByFolder[$0] ?? [] }

        var names = Names()
        for page in all {
            if names.byStem[page.ref.stem] == nil { names.byStem[page.ref.stem] = page.ref }
            if names.byId[page.id] == nil { names.byId[page.id] = page.ref }
            for alias in page.aliases where names.byAlias[alias] == nil { names.byAlias[alias] = page.ref }
        }
        let sourcesDir = root.appending(path: "raw/sources")
        if let sourcesReal = Files.realPath(sourcesDir) {
            for source in Files.pages(in: sourcesDir, folder: "sources", inside: sourcesReal, cache: cache, seen: &seen) {
                if names.sources[source.ref.stem] == nil { names.sources[source.ref.stem] = source.ref.stem }
                if names.sources[source.id] == nil { names.sources[source.id] = source.ref.stem }
            }
        }
        names.anchors = Files.nameIndex(root: root, folder: "_system/anchors", recursive: false)
        names.metamodel = Files.nameIndex(root: root, folder: "_system/metamodel", recursive: true)

        var outgoing: [PageRef: [String: [PageRef]]] = [:]
        var incoming: [PageRef: [String: [PageRef]]] = [:]
        for page in all {
            var perField: [String: [PageRef]] = [:]
            func add(_ links: [Wikilink], field: String) {
                for link in links {
                    guard case .page(let target) = names.resolve(link), target != page.ref,
                          !(perField[field] ?? []).contains(target) else { continue }
                    perField[field, default: []].append(target)
                }
            }
            for (field, links) in page.fieldLinks { add(links, field: field) }
            add(page.bodyLinks, field: "text")
            outgoing[page.ref] = perField
            for (field, targets) in perField {
                for target in targets { incoming[target, default: [:]][field, default: []].append(page.ref) }
            }
        }
        incoming = incoming.mapValues { $0.mapValues { sorted($0) } }
        return Snapshot(folders: folders, pagesByFolder: pagesByFolder, names: names, outgoing: outgoing, incoming: incoming)
    }

    private static let architecture: Set<String> = [
        "solution-strategy", "building-blocks", "crosscutting-concepts", "runtime-scenarios", "deployment-nodes",
    ]
    private static let driverFolders = ["decisions", "solution-strategy", "building-blocks", "crosscutting-concepts", "deployment-nodes"]
    private static let addressable: Set<String> = [
        "goals", "functional-requirements", "quality-requirements", "constraints", "activity-models",
    ]
    private static let realizable: Set<String> = ["functional-requirements", "activity-models"]

    /// The pages the dashboard lists in the trace panel of `ref` (see `PageRelations`).
    func traceTargets(of ref: PageRef) -> Set<PageRef> {
        guard let me = pagesByRef[ref] else { return [] }
        let folder = ref.folder
        var shown = Set<PageRef>()

        func targets(_ page: Page, _ field: String) -> [PageRef] {
            (page.references[field] ?? []).compactMap { names.byStem[$0] }
        }
        func pointing(from folders: [String], _ field: String) {
            for page in folders.flatMap({ pagesByFolder[$0] ?? [] }) where targets(page, field).contains(ref) {
                shown.insert(page.ref)
            }
        }

        let isArchitecture = Self.architecture.contains(folder)
        if isArchitecture || folder == "decisions" {
            shown.formUnion(targets(me, folder == "runtime-scenarios" ? "realizes" : "drivers"))
            shown.formUnion(targets(me, "superseded-by"))
            pointing(from: [folder], "superseded-by")
        }
        if isArchitecture { shown.formUnion(targets(me, "decisions")) }
        if folder == "building-blocks" {
            pointing(from: [folder], "uses")
            pointing(from: ["deployment-nodes"], "hosts")
        }
        if folder == "building-blocks" || folder == "deployment-nodes" { pointing(from: ["crosscutting-concepts"], "applies-to") }
        if ["building-blocks", "deployment-nodes", "external-interfaces", "stakeholders"].contains(folder) {
            pointing(from: ["runtime-scenarios"], "steps")
        }
        if folder == "crosscutting-concepts" { shown.formUnion(targets(me, "applies-to")) }
        if folder == "deployment-nodes" { shown.formUnion(targets(me, "hosts")) }
        if Self.addressable.contains(folder) { pointing(from: Self.driverFolders, "drivers") }
        if Self.realizable.contains(folder) { pointing(from: ["runtime-scenarios"], "realizes") }
        return shown
    }
}

/// File system access. Every file is checked first: it must resolve to a regular file
/// inside the folder it is read for, so a symlink cannot lead out of the wiki.
enum Files {
    /// The path with every symlink resolved, nil when it does not exist, loops or cannot be read.
    static func realPath(_ url: URL) -> String? { realPath(path: url.path) }

    static func realPath(path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func isInside(_ real: String, _ root: String) -> Bool {
        real == root || real.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    static func isFolder(_ url: URL, inside root: String) -> Bool {
        guard let real = realPath(url), isInside(real, root) else { return false }
        return (try? URL(fileURLWithPath: real).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private struct Info {
        let size: Int
        let modified: Date?
    }

    private static func regularFile(_ real: String) -> Info? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? URL(fileURLWithPath: real).resourceValues(forKeys: keys),
              values.isRegularFile == true else { return nil }
        return Info(size: values.fileSize ?? 0, modified: values.contentModificationDate)
    }

    enum Content {
        case text(String, lossy: Bool)
        case tooLarge
        case failed
    }

    /// At most `limit` bytes of a file, read even if the file grows while it is read.
    static func read(_ real: String, limit: Int) -> Content {
        guard let handle = FileHandle(forReadingAtPath: real) else { return .failed }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1) else { return .failed }
        if data.count > limit { return .tooLarge }
        if let text = String(data: data, encoding: .utf8) { return .text(text, lossy: false) }
        return .text(String(decoding: data, as: UTF8.self), lossy: true)
    }

    /// The pages of one folder, in file name order. Reuses a cached page when the file's
    /// modification time and size are the same.
    static func pages(
        in folder: URL, folder name: String, inside root: String,
        cache: [String: CachedPage], seen: inout [String: CachedPage]
    ) -> [Page] {
        var pages: [Page] = []
        for file in names(in: folder) where file.hasSuffix(".md") && !file.hasPrefix(".") {
            let ref = PageRef(folder: name, stem: String(file.dropLast(3)))
            let url = folder.appending(path: file)
            guard ref.isSafe, let real = realPath(url), isInside(real, root), let info = regularFile(real) else { continue }
            let key = url.path
            if let hit = cache[key], hit.size == info.size, hit.modified == info.modified {
                seen[key] = hit
                pages.append(hit.page)
                continue
            }
            let page = load(ref, real: real, size: info.size)
            seen[key] = CachedPage(modified: info.modified, size: info.size, page: page)
            pages.append(page)
        }
        return pages
    }

    private static func load(_ ref: PageRef, real: String, size: Int) -> Page {
        let large = "the file is larger than 5 MB and was not read"
        guard size <= largestPageFile else { return Page(unreadable: ref, because: large) }
        switch read(real, limit: largestPageFile) {
        case .text(let text, let lossy):
            return Page(ref: ref, text: text, readProblems: lossy ? ["the file is not valid UTF-8, bad bytes were replaced"] : [])
        case .tooLarge:
            return Page(unreadable: ref, because: large)
        case .failed:
            return Page(unreadable: ref, because: "the file cannot be read")
        }
    }

    /// Lowercased name, title, alias and file name of each file in a `_system` folder,
    /// mapped to the file's name (else title, else file name). Reads frontmatter only.
    static func nameIndex(root: URL, folder: String, recursive: Bool) -> [String: String] {
        let dir = root.appending(path: folder)
        guard let rootReal = realPath(root), let dirReal = realPath(dir), isInside(dirReal, rootReal) else { return [:] }
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: options) else { return [:] }
        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension == "md" { files.append(url) }
        var index: [String: String] = [:]
        for url in files.sorted(by: { $0.path < $1.path }) {
            guard let real = realPath(url), isInside(real, rootReal), regularFile(real) != nil,
                  case .text(let text, _) = read(real, limit: 1024 * 1024),
                  let yaml = Frontmatter.split(text).yaml else { continue }
            let fields = Frontmatter.read(yaml).fields
            func scalar(_ key: String) -> String? {
                if case .text(let value)? = fields[key], !value.isEmpty { return value }
                return nil
            }
            let stem = url.deletingPathExtension().lastPathComponent
            let canonical = scalar("name") ?? scalar("title") ?? stem
            var keys = [scalar("name"), scalar("title"), stem].compactMap { $0 }
            switch fields["aliases"] {
            case .list(let items)?: keys += items
            case .text(let item)?: keys.append(item)
            default: break
            }
            for key in keys where !key.isEmpty && index[key.lowercased()] == nil { index[key.lowercased()] = canonical }
        }
        return index
    }
}
