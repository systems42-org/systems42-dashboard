import Foundation

/// Where the bundled diagram files are. SwiftPM puts them in `Systems42Dashboard_Systems42UI.bundle/diagram/`.
/// The generated `Bundle.module` stops the program when that bundle is missing, so this looks itself
/// and answers nil: a missing asset shows a plain message in place of the diagram.
enum DiagramAssets {
    static let bundleName = "Systems42Dashboard_Systems42UI.bundle"
    static let folderName = "diagram"
    static let pageName = "index.html"

    private final class Anchor {}

    /// The folders that may hold the resource bundle, in order.
    /// - The app: `Contents/Resources/` (`build-app.sh` copies the bundle there).
    /// - `swift run` and `swift test`: the folder with the built products, next to the executable or the test bundle.
    static var searchFolders: [URL] {
        var folders: [URL] = []
        if let resources = Bundle.main.resourceURL { folders.append(resources) }
        folders.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL { folders.append(executable.deletingLastPathComponent()) }
        folders.append(Bundle(for: Anchor.self).bundleURL.deletingLastPathComponent())
        return folders
    }

    /// Where the files sit inside the resource bundle. `swift build` writes them at its root. The universal
    /// build (`--arch arm64 --arch x86_64`) makes a bundle in the macOS layout, `Contents/Resources/`.
    static let insideBundle = ["", "Contents/Resources"]

    /// The first folder in `places` that holds the bundle with the page in it.
    static func locate(in places: [URL], fileManager: FileManager = .default) -> URL? {
        for place in places {
            let bundle = place.appending(path: bundleName, directoryHint: .isDirectory)
            for inner in insideBundle {
                let folder = (inner.isEmpty ? bundle : bundle.appending(path: inner, directoryHint: .isDirectory))
                    .appending(path: folderName, directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: folder.appending(path: pageName).path) { return folder }
            }
        }
        return nil
    }

    /// The folder of the bundled files, nil when they are missing.
    static var folder: URL? { locate(in: searchFolders) }

    /// The line the hidden `--check-diagram-assets` flag prints.
    static func report(folder: URL?) -> String {
        guard let folder else { return "diagram assets: missing" }
        return "diagram assets: found at \(folder.path)"
    }
}

/// The hidden command-line flag `--check-diagram-assets`: prints whether the bundled files are found and
/// leaves with 0 (all there) or 1, without opening a window. `scripts/build-app.sh` output and CI run it.
public enum DiagramAssetCheck {
    public static let flag = "--check-diagram-assets"

    /// The files the page needs.
    static let files = ["index.html", "diagram.js", "diagram.css", "mermaid.min.js", "cytoscape.min.js", "layout-base.js",
                        "cose-base.js", "cytoscape-fcose.js", "glossary-graph.js", "metamodel-graph.js"]

    /// The report lines and the exit status, nil when the flag is not among the arguments.
    static func run(_ arguments: [String], folder: URL? = DiagramAssets.folder) -> (lines: [String], status: Int32)? {
        guard arguments.contains(flag) else { return nil }
        var lines = [DiagramAssets.report(folder: folder)]
        guard let folder else { return (lines, 1) }
        let missing = files.filter { !FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
        lines += missing.map { "missing file: \($0)" }
        return (lines, missing.isEmpty ? 0 : 1)
    }

    /// Prints the report and returns the exit status, nil when the flag is not among the arguments.
    public static func handle(_ arguments: [String]) -> Int32? {
        guard let result = run(arguments) else { return nil }
        for line in result.lines { print(line) }
        return result.status
    }
}
