import Foundation
import Testing

/// Runs `body`, then fails the test if any file under `wiki` was added, removed,
/// resized or modified. Use it around reads of a temp copy of a fixture.
public func assertUnchanged(
    _ wiki: URL,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) rethrows {
    let before = snapshot(wiki)
    try body()
    #expect(snapshot(wiki) == before, "a file under \(wiki.path) changed", sourceLocation: sourceLocation)
}

private struct FileState: Equatable {
    let size: Int
    let modified: Date?
}

private func snapshot(_ root: URL) -> [String: FileState] {
    var result: [String: FileState] = [:]
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
        return result
    }
    for case let url as URL in walker {
        let values = try? url.resourceValues(forKeys: Set(keys))
        result[url.path] = FileState(size: values?.fileSize ?? -1, modified: values?.contentModificationDate)
    }
    return result
}
