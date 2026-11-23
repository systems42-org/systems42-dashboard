import AppKit
import Foundation
import SwiftUI
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

/// A temp wiki that names `brand:` in its wiki.yaml. The folder holds everything the test writes.
private struct BrandWiki {
    let top: URL
    let wiki: URL

    init(brand: String?) throws {
        wiki = try Fixture.tempCopy("basic")
        top = wiki.deletingLastPathComponent()
        var yaml = "system_name: \"basic fixture\"\n"
        if let brand { yaml += "brand: \(brand)\n" }
        try yaml.write(to: wiki.appending(path: "_system/wiki.yaml"), atomically: true, encoding: .utf8)
    }

    func folder(_ name: String = "brand") throws -> URL {
        let url = wiki.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func load() throws -> Brand {
        let root = try Preflight.open(wiki)
        return Brand.load(root, config: WikiConfig.load(root))
    }

    func remove() { try? FileManager.default.removeItem(at: top) }
}

private func png(width: Int, height: Int) throws -> Data {
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0))
    return try #require(rep.representation(using: .png, properties: [:]))
}

@Suite struct BrandTests {
    @Test func brandFromTheWiki() throws {
        let w = try BrandWiki(brand: "brand/")
        defer { w.remove() }
        try "#1D5FB0\n".write(to: w.folder().appending(path: "accent.txt"), atomically: true, encoding: .utf8)
        let brand = try w.load()
        #expect(brand.accentRGB == BrandColor(red: 0x1D, green: 0x5F, blue: 0xB0))
        #expect(brand.accent == Color(.sRGB, red: Double(0x1D) / 255, green: Double(0x5F) / 255, blue: Double(0xB0) / 255, opacity: 1))
    }

    @Test func aMissingOrBrokenBrandGivesNoAccent() throws {
        // No brand folder at all.
        let none = try BrandWiki(brand: "brand/")
        defer { none.remove() }
        #expect(try none.load() == Brand.none)
        // A folder without a file.
        let empty = try BrandWiki(brand: "brand/")
        defer { empty.remove() }
        _ = try empty.folder()
        #expect(try empty.load().accent == nil)
        // The shipped brand lives in the dashboard, not in the wiki.
        let shipped = try BrandWiki(brand: "systems42")
        defer { shipped.remove() }
        #expect(try shipped.load() == Brand.none)
        // No key.
        let keyless = try BrandWiki(brand: nil)
        defer { keyless.remove() }
        #expect(try keyless.load() == Brand.none)
    }

    @Test func onlyTheStrictFormIsAColour() {
        #expect(BrandColor.parse("#1D5FB0") == BrandColor(red: 0x1D, green: 0x5F, blue: 0xB0))
        #expect(BrandColor.parse("  #1d5fb0\n") == BrandColor(red: 0x1D, green: 0x5F, blue: 0xB0))
        for bad in ["", "red", "1D5FB0", "#1D5FB", "#1D5FB0F", "#1D5FB0FF", "#GGGGGG", "#1D5FB0 x", "rgb(1,2,3)", "#１２３４５６",
                    "#1D5FB0\n#000000", "##1D5FB0", "#+1D5FB"] {
            #expect(BrandColor.parse(bad) == nil, "\(bad)")
        }
    }

    @Test func brokenAccentFilesGiveNil() throws {
        for content in ["red", "#12", "#1D5FB0 and more", "{\"accent\": \"#1D5FB0\"}"] {
            let w = try BrandWiki(brand: "brand")
            defer { w.remove() }
            try content.write(to: w.folder().appending(path: "accent.txt"), atomically: true, encoding: .utf8)
            #expect(try w.load().accent == nil, "\(content)")
        }
    }

    @Test func aLargeAccentFileIsNotRead() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        try ("#1D5FB0" + String(repeating: " ", count: 4096)).write(to: w.folder().appending(path: "accent.txt"), atomically: true, encoding: .utf8)
        #expect(try w.load().accent == nil)
    }

    @Test func brandFileOutsideTheWikiIsIgnored() throws {
        let w = try BrandWiki(brand: "../../x")
        defer { w.remove() }
        #expect(try w.load() == Brand.none)
        // The folder one level up, which exists and holds a valid accent.
        let up = try BrandWiki(brand: "../sibling")
        defer { up.remove() }
        let sibling = up.top.appending(path: "sibling")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try "#1D5FB0".write(to: sibling.appending(path: "accent.txt"), atomically: true, encoding: .utf8)
        #expect(try up.load() == Brand.none)
        // An absolute path.
        let absolute = try BrandWiki(brand: sibling.path)
        defer { absolute.remove() }
        #expect(try absolute.load() == Brand.none)
    }

    @Test func aBrandFolderThatIsASymlinkOutIsIgnored() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        let outside = w.top.appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "#1D5FB0".write(to: outside.appending(path: "accent.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: w.wiki.appending(path: "brand"), withDestinationURL: outside)
        #expect(try w.load() == Brand.none)
    }

    @Test func anAccentFileThatIsASymlinkOutIsIgnored() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        let outside = w.top.appending(path: "secret.txt")
        try "#1D5FB0".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: w.folder().appending(path: "accent.txt"), withDestinationURL: outside)
        #expect(try w.load().accent == nil)
    }

    // MARK: Contrast

    @Test func contrastFollowsTheWebFormula() {
        #expect(abs(BrandColor.white.contrast(with: BrandColor(red: 0, green: 0, blue: 0)) - 21) < 0.01)
        #expect(abs(BrandColor.white.contrast(with: .white) - 1) < 0.001)
    }

    @Test func anUnreadableAccentFallsBackToTheSystemAccent() throws {
        #expect(Brand.minimumTextContrast == 4.5)
        for (hex, readable) in [("#1D5FB0", true), ("#B03A3A", true), ("#FFD60A", false), ("#FF9500", false),
                                ("#000000", false), ("#001F3F", false), ("#FFFFFF", false)] {
            let w = try BrandWiki(brand: "brand")
            defer { w.remove() }
            try hex.write(to: w.folder().appending(path: "accent.txt"), atomically: true, encoding: .utf8)
            #expect((try w.load().accent != nil) == readable, "\(hex)")
        }
    }

    // MARK: Mark

    @Test func aPngMarkInsideTheBrandFolderIsLoaded() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        try png(width: 64, height: 64).write(to: w.folder().appending(path: "mark.png"))
        let mark = try #require(try w.load().mark)
        #expect(mark.lastPathComponent == "mark.png")
    }

    @Test func aMarkThatIsNotAnImageOfTheAllowedTypesIsIgnored() throws {
        // SVG is the dashboard's mark format. The app does not decode it.
        let svg = try BrandWiki(brand: "brand")
        defer { svg.remove() }
        try "<svg xmlns=\"http://www.w3.org/2000/svg\"/>".write(to: svg.folder().appending(path: "mark.svg"), atomically: true, encoding: .utf8)
        try "<svg xmlns=\"http://www.w3.org/2000/svg\"/>".write(to: svg.folder().appending(path: "mark-dark.svg"), atomically: true, encoding: .utf8)
        #expect(try svg.load().mark == nil)
        // Text under an image name.
        let fake = try BrandWiki(brand: "brand")
        defer { fake.remove() }
        try "not an image".write(to: fake.folder().appending(path: "mark.png"), atomically: true, encoding: .utf8)
        #expect(try fake.load().mark == nil)
        // A TIFF named .png.
        let tiff = try BrandWiki(brand: "brand")
        defer { tiff.remove() }
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(rep.representation(using: .tiff, properties: [:])).write(to: tiff.folder().appending(path: "mark.png"))
        #expect(try tiff.load().mark == nil)
    }

    @Test func aLargeMarkIsIgnored() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        var data = try png(width: 8, height: 8)
        data.append(Data(count: Brand.largestMarkBytes))
        try data.write(to: w.folder().appending(path: "mark.png"))
        #expect(try w.load().mark == nil)
    }

    @Test func aMarkWithTooManyPixelsIsIgnored() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        try png(width: Brand.largestMarkSide + 1, height: 1).write(to: w.folder().appending(path: "mark.png"))
        #expect(try w.load().mark == nil)
    }

    @Test func aMarkThatIsASymlinkOutIsIgnored() throws {
        let w = try BrandWiki(brand: "brand")
        defer { w.remove() }
        let outside = w.top.appending(path: "o.png")
        try png(width: 8, height: 8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: w.folder().appending(path: "mark.png"), withDestinationURL: outside)
        #expect(try w.load().mark == nil)
    }
}
