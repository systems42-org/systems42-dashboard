import Foundation
import Systems42Kit

/// A folder that is not a wiki, and what it lacks.
public struct PreflightFailure: Equatable, Sendable {
    public let folder: URL
    public let missing: [String]
}

/// The result of opening a folder.
public enum OpenedWiki {
    case session(WikiSession)
    case failed(PreflightFailure)

    /// Checks the folder, then reads it off the main thread.
    @MainActor public static func open(_ folder: URL) async -> OpenedWiki {
        do {
            return .session(await WikiSession.open(try Preflight.open(folder)))
        } catch PreflightError.missing(let parts) {
            return .failed(PreflightFailure(folder: folder, missing: parts))
        } catch {
            return .failed(PreflightFailure(folder: folder, missing: Preflight.required))
        }
    }
}
