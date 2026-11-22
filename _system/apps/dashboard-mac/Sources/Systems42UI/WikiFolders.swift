import Foundation
import SwiftUI

/// Which URLs and arguments become wiki windows. Every folder that becomes a window value
/// goes through `standardized`, so two spellings of one folder give one window.
public enum WikiFolders {
    /// An absolute directory URL without `..`, `.` or a trailing slash difference.
    public static func standardized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    /// The folder named on the command line. `arguments` excludes the program name.
    /// The first argument that does not start with `-` and is not the value of a flag
    /// before it. A relative path is resolved against `currentDirectory`.
    public static func fromArguments(_ arguments: [String], currentDirectory: String) -> URL? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-") {
                index += (index + 1 < arguments.count && !arguments[index + 1].hasPrefix("-")) ? 2 : 1
                continue
            }
            let base = URL(fileURLWithPath: currentDirectory, isDirectory: true)
            return standardized(URL(fileURLWithPath: argument, isDirectory: true, relativeTo: base))
        }
        return nil
    }

    /// The folders among `urls`, standardized, each once, in order. Files and other URLs are dropped.
    public static func fromOpened(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { url -> URL? in
            var isDirectory: ObjCBool = false
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            let folder = standardized(url)
            return seen.insert(folder).inserted ? folder : nil
        }
    }

    /// Labels for a menu: the folder name, and the parent folder too when two entries share a name.
    public static func labels(for folders: [URL]) -> [String] {
        let counts = Dictionary(folders.map { ($0.lastPathComponent, 1) }, uniquingKeysWith: +)
        return folders.map { url in
            let name = url.lastPathComponent
            guard counts[name, default: 0] > 1 else { return name }
            return "\(name) (\(url.deletingLastPathComponent().lastPathComponent))"
        }
    }
}

extension OpenWindowAction {
    /// Opens the window of a wiki folder, or brings the one that shows it to the front.
    public func openWiki(_ folder: URL) {
        callAsFunction(value: WikiFolders.standardized(folder))
    }
}

extension View {
    /// Opens a wiki window for each folder the system hands to the app, such as a folder
    /// dropped on the Dock icon.
    public func opensDroppedFolders() -> some View {
        modifier(OpensDroppedFolders())
    }
}

private struct OpensDroppedFolders: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            for folder in WikiFolders.fromOpened([url]) { openWindow.openWiki(folder) }
        }
    }
}
