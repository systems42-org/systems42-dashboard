import Foundation
import ImageIO
import SwiftUI
import Systems42Kit

/// An sRGB colour with 8 bits per channel, from the strict form `#RRGGBB`.
public struct BrandColor: Equatable, Sendable {
    public let red: UInt8, green: UInt8, blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = BrandColor(red: 255, green: 255, blue: 255)

    /// Exactly `#` and six hex digits (ASCII), around which white space is allowed. Nothing else is a colour.
    public static func parse(_ text: String) -> BrandColor? {
        let digits = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard digits.count == 7, digits[0] == UInt8(ascii: "#") else { return nil }
        var values: [UInt8] = []
        for pair in stride(from: 1, to: 7, by: 2) {
            guard let high = hex(digits[pair]), let low = hex(digits[pair + 1]) else { return nil }
            values.append(high * 16 + low)
        }
        return BrandColor(red: values[0], green: values[1], blue: values[2])
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// The relative luminance of WCAG 2.
    var luminance: Double {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The contrast ratio of WCAG 2, from 1 to 21.
    public func contrast(with other: BrandColor) -> Double {
        let (high, low) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (high + 0.05) / (low + 0.05)
    }

    public var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }
}

/// The look a wiki asks for (FR-031, shrunk to what a native app can honour): an accent colour and a mark.
/// `brand:` in `_system/wiki.yaml` names a folder of the wiki, as in the dashboard. In that folder:
/// - `accent.txt` holds `#RRGGBB` and nothing else (at most 64 bytes).
/// - `mark.png`, `mark.jpg` or `mark.jpeg` is the mark. The dashboard's SVG marks are not decoded here.
///
/// The shipped brand `systems42` lives in the dashboard, not in the wiki: it gives no accent and no mark.
/// Anything missing, outside the wiki, too large or unreadable gives nil, never an error.
public struct Brand: Equatable, Sendable {
    public let accent: Color?
    public let accentRGB: BrandColor?
    public let mark: URL?

    public static let none = Brand(accentRGB: nil, mark: nil)

    /// The text of the selected row is white in light and dark appearance. The accent must reach this contrast with it (WCAG AA).
    public static let minimumTextContrast = 4.5
    /// In dark appearance the accent also shows as a mark on the sidebar's background. It must stand out from it by this much.
    public static let minimumSurfaceContrast = 1.5
    /// The colour of the sidebar's background in dark appearance.
    static let darkSidebar = BrandColor(red: 0x1E, green: 0x1E, blue: 0x1E)

    public static let largestAccentFileBytes = 64
    public static let largestMarkBytes = 1_000_000
    /// The most pixels along either side of a mark.
    public static let largestMarkSide = 2048

    private static let markFiles = ["mark.png", "mark.jpg", "mark.jpeg"]
    private static let markTypes: Set<String> = ["public.png", "public.jpeg"]

    private init(accentRGB: BrandColor?, mark: URL?) {
        self.accentRGB = accentRGB
        accent = accentRGB?.color
        self.mark = mark
    }

    public static func load(_ root: WikiRoot, config: WikiConfig) -> Brand {
        guard !shipped.contains(config.brand), let folder = Preflight.contained(config.brand, in: root),
              (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return .none }
        return Brand(accentRGB: accent(in: folder, root: root, brand: config.brand), mark: mark(in: folder, root: root, brand: config.brand))
    }

    /// The brand names the dashboard ships.
    private static let shipped: Set<String> = ["systems42"]

    private static func file(_ name: String, brand: String, root: WikiRoot, largest: Int) -> URL? {
        let relative = brand.hasSuffix("/") ? brand + name : brand + "/" + name
        guard let url = Preflight.contained(relative, in: root),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= largest else { return nil }
        return url
    }

    private static func accent(in folder: URL, root: WikiRoot, brand: String) -> BrandColor? {
        guard let url = file("accent.txt", brand: brand, root: root, largest: largestAccentFileBytes),
              let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
              let color = BrandColor.parse(text) else { return nil }
        let readable = color.contrast(with: .white) >= minimumTextContrast
            && color.contrast(with: darkSidebar) >= minimumSurfaceContrast
        return readable ? color : nil
    }

    private static func mark(in folder: URL, root: WikiRoot, brand: String) -> URL? {
        for name in markFiles {
            guard let url = file(name, brand: brand, root: root, largest: largestMarkBytes), isSafeImage(url) else { continue }
            return url
        }
        return nil
    }

    /// A PNG or JPEG by its content, not its name, and no larger than `largestMarkSide` in either direction.
    /// The check reads the header and the properties, it decodes no pixels.
    private static func isSafeImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?, markTypes.contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return (1...largestMarkSide).contains(width) && (1...largestMarkSide).contains(height)
    }
}
