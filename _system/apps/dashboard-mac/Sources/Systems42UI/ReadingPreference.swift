import Foundation
import Observation

/// The reader's choice between the formatted page and the plain one (FR-049).
/// It belongs to the app, so it lives in the user defaults and never in the wiki.
@MainActor @Observable public final class ReadingPreference {
    public static let shared = ReadingPreference()
    static let key = "plainReading"

    @ObservationIgnored private let defaults: UserDefaults

    /// True while links show only their text.
    public var plain: Bool {
        didSet { defaults.set(plain, forKey: Self.key) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plain = defaults.bool(forKey: Self.key)
    }
}
