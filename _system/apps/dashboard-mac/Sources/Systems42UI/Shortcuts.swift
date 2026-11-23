import SwiftUI

/// Every keyboard shortcut of the app in one list, so a clash shows in one place. A test checks that
/// no two are equal and that none takes a key the system keeps.
public struct Shortcut: Sendable {
    public let name: String
    /// The shortcut as the menu writes it, for example `⇧⌘L`.
    public let keys: String
    public let key: KeyEquivalent
    public let modifiers: EventModifiers

    init(_ name: String, _ key: Character, _ modifiers: EventModifiers = .command) {
        self.name = name
        self.key = KeyEquivalent(key)
        self.modifiers = modifiers
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        keys = text + String(key).uppercased()
    }

    /// For the keys SwiftUI names, such as the arrows.
    init(_ name: String, keys: String, key: KeyEquivalent, modifiers: EventModifiers) {
        self.name = name
        self.keys = keys
        self.key = key
        self.modifiers = modifiers
    }
}

extension View {
    /// Attaches a shortcut of the list.
    public func shortcut(_ shortcut: Shortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

public enum Shortcuts {
    public static let openFolder = Shortcut("Open Folder", "o")
    public static let readingView = Shortcut("Reading View", "r", [.command, .shift])
    public static let agreedOnly = Shortcut("Agreed Only", "a", [.command, .shift])
    public static let showInList = Shortcut("Show in List", "l", [.command, .shift])
    public static let search = Shortcut("Search", "k")
    public static let find = Shortcut("Find", "f")
    public static let back = Shortcut("Back", "[")
    public static let forward = Shortcut("Forward", "]")
    public static let copyLink = Shortcut("Copy Link", "c", [.command, .shift])
    public static let openInObsidian = Shortcut("Open in Obsidian", "o", [.command, .shift])
    public static let metamodel = Shortcut("Metamodel", "m", [.command, .shift])
    public static let help = Shortcut("Systems42 Dashboard Help", keys: "⌘?", key: "/", modifiers: [.command, .shift])
    public static let previousTourStep = Shortcut("Previous Tour Step", keys: "⌥⌘←", key: .leftArrow, modifiers: [.command, .option])
    public static let nextTourStep = Shortcut("Next Tour Step", keys: "⌥⌘→", key: .rightArrow, modifiers: [.command, .option])
    public static let stopTour = Shortcut("Stop Tour", keys: "⎋", key: .escape, modifiers: [])

    /// Cmd-1 to Cmd-9.
    public static let sections: [Shortcut] = (1...9).map { Shortcut("Section \($0)", Character(String($0))) }

    public static var all: [Shortcut] {
        [openFolder, readingView, agreedOnly, showInList, search, find, back, forward, copyLink, openInObsidian, metamodel, help,
         previousTourStep, nextTourStep, stopTour] + sections
    }
}
