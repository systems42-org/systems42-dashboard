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
