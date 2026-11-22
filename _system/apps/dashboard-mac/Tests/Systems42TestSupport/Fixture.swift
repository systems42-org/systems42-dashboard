import Foundation

/// Locates the frozen Systems42 derivatives under `Tests/Fixtures/`.
public enum Fixture {
    public static let names = ["basic", "search", "arc42", "arc42-views", "domain-model"]

    /// The root folder of one fixture, which holds `wiki/`, `raw/` and `_system/`.
    public static func url(_ name: String) -> URL {
        testsDirectory.appending(path: "Fixtures").appending(path: name)
    }

    private static let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

extension Fixture {
    /// A copy of one fixture in a new temp folder, for tests that edit files or
    /// add hostile ones. Never edit a fixture in place.
    public static func tempCopy(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "s42-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "wiki-copy")
        try FileManager.default.copyItem(at: url(name), to: copy)
        return copy
    }
}
