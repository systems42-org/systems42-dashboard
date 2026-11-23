import Foundation

public enum AppInfo {
    public static let windowTitle = "Systems42 Dashboard"
}

extension AppInfo {
    /// The version of the app: the dashboard release it was built from. A build without a bundle (`swift run`) has none.
    public static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "development"
    }
}
