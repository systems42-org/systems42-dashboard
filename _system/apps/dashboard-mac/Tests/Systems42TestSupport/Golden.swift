import Foundation

/// Reads the golden data under `Tests/Golden/<fixture>/`, which the Go dashboard
/// produced and `scripts/export-golden.sh` wrote.
public enum Golden {
    public static func url(_ fixture: String, _ file: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Golden")
            .appending(path: fixture)
            .appending(path: file)
    }

    public static func exists(_ fixture: String, _ file: String) -> Bool {
        FileManager.default.fileExists(atPath: url(fixture, file).path)
    }

    /// Parses a golden JSON file. Throws when the file is missing or not JSON.
    public static func json(_ fixture: String, _ file: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url(fixture, file)))
    }

    /// Reads a golden text file, such as a Mermaid diagram.
    public static func text(_ fixture: String, _ file: String) throws -> String {
        try String(contentsOf: url(fixture, file), encoding: .utf8)
    }

    /// The names of the files in `diagrams/`, sorted.
    public static func diagrams(_ fixture: String) -> [String] {
        let dir = url(fixture, "diagrams")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted()
    }
}
