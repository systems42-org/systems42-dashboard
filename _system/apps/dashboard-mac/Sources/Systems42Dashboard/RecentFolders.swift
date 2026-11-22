import Foundation
import Observation
import Systems42Kit

/// The recent wikis, kept under Application Support and never inside a wiki.
@MainActor @Observable final class RecentFolders {
    private(set) var urls: [URL] = []
    private var store: RecentWikis

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = RecentWikis(storage: support.appending(path: "Systems42 Dashboard Native"))
        urls = store.list()
    }

    func note(_ url: URL) {
        store.note(url)
        urls = store.list()
    }
}
