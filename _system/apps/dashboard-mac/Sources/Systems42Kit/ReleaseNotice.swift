/// FR-055: tells the reader when a wiki names another dashboard version than the app.
public enum ReleaseNotice {
    /// `nil` when the wiki names no version, `local`, or the app's own version.
    public static func text(wikiNames: String?, appVersion: String) -> String? {
        guard let named = wikiNames, !named.isEmpty, named != "local", named != appVersion else { return nil }
        return "This wiki names dashboard version \(named). This app is version \(appVersion)."
    }
}
