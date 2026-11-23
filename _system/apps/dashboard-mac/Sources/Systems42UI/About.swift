import AppKit
import Foundation
import Observation
import SwiftUI
import Systems42Kit

/// What the About window shows: the app, and the wiki of the focused window if there is one.
public struct AboutModel: Equatable {
    public struct Wiki: Equatable {
        public let name: String
        public let folder: URL
        /// The folder as the window shows it: home written as `~`, cleaned, bounded.
        public let folderText: String
        /// The dashboard release the wiki names in `wiki.yaml`, nil when it names none.
        public let release: String?
        /// FR-055: set when the wiki names a release other than the app's.
        public let notice: String?
        /// The metamodel version the wiki declares, or that it names none.
        public let metamodel: String
        public let metamodelNotice: String?
        public let supportedVersions: [String]
        public let refreshed: Date
        /// The brand `wiki.yaml` names. Shown as text: how the app shows a brand is not decided.
        public let brand: String
    }

    public let appVersion: String
    public let wiki: Wiki?

    @MainActor public init(appVersion: String, session: WikiSession?) {
        self.appVersion = appVersion
        guard let session else {
            wiki = nil
            return
        }
        // Everything that comes from the wiki is cleaned: one line, no control or format characters, bounded.
        let release = session.config.dashboardVersion.map { Untrusted.clean($0) }
        wiki = Wiki(
            name: Untrusted.clean(session.title, longest: 80),
            folder: session.root.url,
            folderText: Untrusted.clean((session.root.url.path as NSString).abbreviatingWithTildeInPath, longest: 200),
            release: release,
            notice: ReleaseNotice.text(wikiNames: release, appVersion: appVersion).map { Untrusted.clean($0, longest: 200) },
            metamodel: Untrusted.clean(Self.metamodelLine(session.metamodel.version)),
            metamodelNotice: MetamodelModel.notice(for: session.metamodel.version).map { Untrusted.clean($0.line, longest: 200) },
            supportedVersions: Metamodel.supportedVersions,
            refreshed: session.refreshedAt,
            brand: Untrusted.clean(session.config.brand, longest: 80))
    }

    static func metamodelLine(_ state: VersionState) -> String {
        switch state {
        case .supported(let version): version
        case .unsupported(let found, _): found
        case .missing: "names no version"
        }
    }
}

/// The wiki the About window shows: the one that was focused when the reader chose About.
@MainActor @Observable public final class AboutContext {
    public static let shared = AboutContext()
    public var folder: URL?
}

/// The About window. It looks the session up on every read, so it never keeps a closed wiki alive.
public struct AboutWindowRoot: View {
    public static let windowID = "about"
    @Bindable private var context = AboutContext.shared

    public init() {}

    public var body: some View {
        let session = context.folder.flatMap { OpenSessions.shared.session(for: $0) }
        AboutView(model: AboutModel(appVersion: AppInfo.version, session: session))
    }
}

struct AboutView: View {
    let model: AboutModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.windowTitle).font(.title2.bold())
                    Text("Version \(model.appVersion)").foregroundStyle(.secondary)
                }
            }
            if let wiki = model.wiki {
                Divider()
                Text(wiki.name).font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    row("Folder", wiki.folderText)
                    row("Dashboard release", wiki.release ?? "not named")
                    row("Brand", wiki.brand)
                    row("Metamodel", wiki.metamodel)
                    row("Supported", wiki.supportedVersions.joined(separator: ", "))
                    row("Read", wiki.refreshed.formatted(date: .abbreviated, time: .standard))
                }
                if let notice = wiki.notice { Text(notice).foregroundStyle(.orange) }
                if let notice = wiki.metamodelNotice { Text(notice).foregroundStyle(.orange) }
            }
        }
        .textSelection(.enabled)
        .padding(20)
        .frame(width: 440, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(verbatim: value).lineLimit(2).truncationMode(.middle)
        }
    }
}
