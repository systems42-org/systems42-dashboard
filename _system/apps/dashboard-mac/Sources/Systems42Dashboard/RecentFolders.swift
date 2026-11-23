import Foundation
import Observation
import Systems42Kit
import Systems42UI

/// The recent wikis, kept under Application Support and never inside a wiki.
@MainActor @Observable final class RecentFolders {
    static let shared = RecentFolders()
    private(set) var urls: [URL] = []
    private var store: RecentWikis

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = RecentWikis(storage: support.appending(path: "Systems42 Dashboard Native"))
        urls = store.list().map(WikiFolders.standardized)
    }

    func note(_ url: URL) {
        store.note(WikiFolders.standardized(url))
        urls = store.list().map(WikiFolders.standardized)
    }
}
