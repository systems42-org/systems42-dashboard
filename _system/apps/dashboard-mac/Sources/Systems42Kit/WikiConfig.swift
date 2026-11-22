import Foundation
import Yams

/// The project identity from `_system/wiki.yaml`.
public struct WikiConfig: Sendable {
    public var systemName = "Requirements Wiki"
    public var tagline = ""
    public var brand = "systems42"
    public var dashboardVersion: String?

    /// Reads the file fresh on each call. A missing, empty or broken file gives the defaults.
    public static func load(_ root: WikiRoot) -> WikiConfig {
        var config = WikiConfig()
        let file = root.url.appending(path: "_system/wiki.yaml")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let map = (try? Yams.load(yaml: text)) as? [String: Any]
        else { return config }

        if let name = scalar(map["system_name"]), !name.isEmpty { config.systemName = name }
        config.tagline = scalar(map["tagline"]) ?? ""
        // The Go reader accepts only text for `brand`.
        if let brand = (map["brand"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            config.brand = brand
        }
        if let version = scalar(map["dashboard_version"]) { config.dashboardVersion = version }
        return config
    }

    private static func scalar(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
