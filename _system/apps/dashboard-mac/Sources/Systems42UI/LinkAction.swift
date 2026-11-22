import Foundation
import SwiftUI
import Systems42Kit

/// What a click on a link does. It travels as a URL, so the text view can carry it.
/// The only outside URLs it takes are http, https and mailto, as the Kit produces no others.
enum LinkAction: Equatable, Sendable {
    case page(PageRef)
    case anchor(String)
    case web(URL)

    private static let scheme = "systems42"
    private static let webSchemes: Set<String> = ["http", "https", "mailto"]

    var isPage: Bool {
        if case .page = self { true } else { false }
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .page(let ref):
            parts.host = "page"
            parts.queryItems = [URLQueryItem(name: "folder", value: ref.folder), URLQueryItem(name: "stem", value: ref.stem)]
        case .anchor(let name):
            parts.host = "anchor"
            parts.queryItems = [URLQueryItem(name: "name", value: name)]
        case .web(let url):
            return url
        }
        return parts.url ?? URL(string: "\(Self.scheme):")!
    }

    init?(url: URL) {
        if let scheme = url.scheme?.lowercased(), Self.webSchemes.contains(scheme) {
            self = .web(url)
            return
        }
        guard url.scheme == Self.scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func value(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        switch parts.host {
        case "page":
            guard let folder = value("folder"), let stem = value("stem") else { return nil }
            self = .page(PageRef(folder: folder, stem: stem))
        case "anchor":
            guard let name = value("name") else { return nil }
            self = .anchor(name)
        default:
            return nil
        }
    }
}

/// Inlines as one styled text, and the actions of the links in it in order.
/// Text stays text: markup in a page is shown as typed and no link comes out of it
/// except the ones the Kit resolved.
struct InlineContent {
    private(set) var text = AttributedString()
    private(set) var actions: [LinkAction] = []

    init(_ inlines: [Inline]) {
        for inline in inlines { append(inline, bold: false, italic: false, link: nil, missing: false) }
    }

    init(_ inline: Inline) {
        self.init([inline])
    }

    private mutating func append(_ inline: Inline, bold: Bool, italic: Bool, link: URL?, missing: Bool) {
        switch inline {
        case .text(let value):
            add(value, bold: bold, italic: italic, link: link, missing: missing, code: false)
        case .code(let value):
            add(value, bold: bold, italic: italic, link: link, missing: missing, code: true)
        case .emphasis(let inner):
            for item in inner { append(item, bold: bold, italic: true, link: link, missing: missing) }
        case .strong(let inner):
            for item in inner { append(item, bold: true, italic: italic, link: link, missing: missing) }
        case .link(let label, let target, _):
            var url: URL?
            var absent = false
            switch target {
            case .page(let ref): url = LinkAction.page(ref).url
            case .anchor(let name): url = LinkAction.anchor(name).url
            case .missing: absent = true
            case .source, .metamodel: break
            }
            if let url { actions.append(LinkAction(url: url)!) }
            for item in label { append(item, bold: bold, italic: italic, link: url, missing: absent) }
        case .url(let label, let address):
            // The Kit gives no other scheme. A page must not get one through here either.
            let action = LinkAction(url: address)
            if case .web? = action { actions.append(.web(address)) }
            let url: URL? = if case .web? = action { address } else { nil }
            for item in label { append(item, bold: bold, italic: italic, link: url, missing: false) }
        }
    }

    private mutating func add(_ value: String, bold: Bool, italic: Bool, link: URL?, missing: Bool, code: Bool) {
        var run = AttributedString(value)
        var intent: InlinePresentationIntent = []
        if bold { intent.insert(.stronglyEmphasized) }
        if italic { intent.insert(.emphasized) }
        if !intent.isEmpty { run.inlinePresentationIntent = intent }
        if code { run.font = .system(.body, design: .monospaced) }
        if let link { run.link = link }
        if missing {
            run.foregroundColor = .secondary
            run.underlineStyle = Text.LineStyle(pattern: .dot)
        }
        text.append(run)
    }
}
