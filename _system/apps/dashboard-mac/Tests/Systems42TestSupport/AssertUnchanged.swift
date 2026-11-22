import Foundation
import Testing

/// Runs `body`, then fails the test if any file under `wiki` was added, removed,
/// resized or modified. Use it around reads of a temp copy of a fixture.
/// It also fails when it cannot list the folder, so an unreadable folder never
/// passes as "unchanged".
public func assertUnchanged(
    _ wiki: URL,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) rethrows {
    let before = snapshot(wiki)
    #expect(before != nil, "cannot list \(wiki.path)", sourceLocation: sourceLocation)
    try body()
    let after = snapshot(wiki)
    #expect(after != nil, "cannot list \(wiki.path)", sourceLocation: sourceLocation)
    if let before, let after {
        #expect(after == before, "a file under \(wiki.path) changed", sourceLocation: sourceLocation)
    }
}

private struct FileState: Equatable {
    let size: Int
    let modified: Date?
}

private final class Failure: @unchecked Sendable {
    var happened = false
}

/// Size and modification time of every entry under `root`, or nil when the
/// folder, or anything inside it, cannot be listed.
private func snapshot(_ root: URL) -> [String: FileState]? {
    guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else { return nil }
    let failure = Failure()
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    guard let walker = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        errorHandler: { _, _ in failure.happened = true; return true }
    ) else { return nil }
    var result: [String: FileState] = [:]
    for case let url as URL in walker {
        let values = try? url.resourceValues(forKeys: Set(keys))
        result[url.path] = FileState(size: values?.fileSize ?? -1, modified: values?.contentModificationDate)
    }
    return failure.happened ? nil : result
}
