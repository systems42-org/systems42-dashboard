import Foundation

/// An opened wiki folder. Only `Preflight.open` makes one.
public struct WikiRoot: Hashable, Sendable {
    public let url: URL

    init(url: URL) { self.url = url }
}

public enum PreflightError: Error, Equatable, Sendable {
    /// The parts of `Preflight.required` the folder lacks, in that order.
    case missing([String])
}

/// Checks that a folder is a Systems42 derivative (CON-005).
public enum Preflight {
    public static let required = ["wiki", "raw", "_system/wiki.yaml", "_system/metamodel", "_system/anchors"]

    private static let files: Set<String> = ["_system/wiki.yaml"]

    /// The entries of `required` the folder lacks. A file where a folder belongs
    /// (or the reverse) counts as missing.
    public static func missing(in url: URL) -> [String] {
        required.filter { part in
            var isDirectory: ObjCBool = false
            let path = url.appending(path: part).path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return true }
            return isDirectory.boolValue == files.contains(part)
        }
    }

    public static func open(_ url: URL) throws -> WikiRoot {
        let parts = missing(in: url)
        guard parts.isEmpty else { throw PreflightError.missing(parts) }
        return WikiRoot(url: url)
    }

    /// The file or folder `relative` names under the wiki root, with every symlink resolved, or nil
    /// when it does not exist or resolves outside the root. An empty, absolute or `..` path gives nil
    /// too. Use it for any path a wiki file or a page names.
    public static func contained(_ relative: String, in root: WikiRoot) -> URL? {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.hasPrefix("~"),
              !relative.split(separator: "/").contains("..") else { return nil }
        guard let rootReal = Files.realPath(root.url),
              let real = Files.realPath(root.url.appending(path: relative)),
              Files.isInside(real, rootReal) else { return nil }
        return URL(fileURLWithPath: real)
    }
}
