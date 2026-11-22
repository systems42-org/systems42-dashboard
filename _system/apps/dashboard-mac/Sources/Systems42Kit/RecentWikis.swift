import Foundation

/// The wikis opened lately, kept in a file in `storage`. Never write into a wiki.
public struct RecentWikis {
    private static let limit = 10
    private let file: URL

    /// `storage` is a folder under Application Support, never inside a wiki.
    public init(storage: URL) {
        file = storage.appending(path: "recent-wikis.json")
    }

    /// Newest first, at most 10. Folders that are gone are left out.
    public func list() -> [URL] {
        stored()
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public mutating func note(_ url: URL) {
        let path = url.standardizedFileURL.path
        let paths = ([path] + stored().filter { $0 != path }).prefix(Self.limit)
        guard let data = try? JSONEncoder().encode(Array(paths)) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private func stored() -> [String] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
