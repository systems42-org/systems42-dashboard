import Foundation
import Systems42TestSupport
@testable import Systems42Kit

/// The projections of one fixture.
func projections(_ fixture: String, agreedOnly: Bool = false) throws -> Projections {
    let store = WikiStore(root: try Preflight.open(Fixture.url(fixture)))
    return Projections(store: store, metamodel: store.metamodel, agreedOnly: agreedOnly)
}

/// A small wiki in a temp folder, with the metamodel of `basic`, for tests that need their own pages.
struct TempWiki {
    let url: URL

    /// `metamodel: false` leaves `_system/metamodel/` empty.
    init(metamodel: Bool = true) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "s42-proj-\(UUID().uuidString)")
        url = folder
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appending(path: "wiki"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appending(path: "raw"), withIntermediateDirectories: true)
        let source = Fixture.url("basic").appending(path: "_system")
        try fm.copyItem(at: source, to: folder.appending(path: "_system"))
        try "system_name: System X\n".write(to: folder.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
        if !metamodel {
            let dir = folder.appending(path: "_system/metamodel")
            try fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Writes `wiki/<folder>/<stem>.md`. The id is the first two parts of the stem. `fields` are
    /// written as `key: value` lines, in order.
    /// `yamlID` replaces the id, as YAML text (quote it).
    func page(_ folder: String, _ stem: String, _ title: String, _ status: String, _ fields: [(String, String)] = [],
              yamlID: String? = nil) throws {
        let dir = url.appending(path: "wiki").appending(path: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = stem.split(separator: "-").prefix(2).joined(separator: "-")
        let extra = fields.map { "\($0.0): \($0.1)\n" }.joined()
        let related = fields.contains { $0.0 == "related" } ? "" : "related: []\n"
        let text = "---\nid: \(yamlID ?? id)\ntitle: \(title)\nstatus: \(status)\nsources: []\n\(related)\(extra)---\n\n# \(title)\n"
        try text.write(to: dir.appending(path: "\(stem).md"), atomically: true, encoding: .utf8)
    }

    func projections(agreedOnly: Bool = false) throws -> Projections {
        let store = WikiStore(root: try Preflight.open(url))
        return Projections(store: store, metamodel: store.metamodel, agreedOnly: agreedOnly)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
