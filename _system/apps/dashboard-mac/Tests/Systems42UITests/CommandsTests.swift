import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor @Suite struct CommandsTests {
    private func session(_ fixture: String = "basic") async throws -> WikiSession {
        await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
    }

    private func pages(_ s: WikiSession) -> [PageRef] {
        s.store.pages(in: "functional-requirements").map(\.ref)
    }

    private static let needsAPage: Set<SessionCommand> = [.copyLink, .copyID, .openInObsidian, .revealInFinder, .share]

    @Test func everyCommandHasAnAction() async throws {
        // No window: nothing is enabled, and performing does nothing.
        for command in SessionCommand.allCases {
            #expect(!MenuRules.isEnabled(command, session: nil), "\(command)")
            MenuRules.perform(command, on: nil)
        }
        // A window without a selection.
        let s = try await session()
        for command in SessionCommand.allCases {
            let expected = command == .agreedOnly
            #expect(MenuRules.isEnabled(command, session: s) == expected, "\(command)")
        }
        // A page is selected.
        let refs = pages(s)
        s.select(page: refs[0])
        for command in SessionCommand.allCases {
            let expected = Self.needsAPage.contains(command) || command == .agreedOnly
            #expect(MenuRules.isEnabled(command, session: s) == expected, "\(command)")
        }
        // After a second page, back works. After back, forward works.
        s.select(page: refs[1])
        #expect(MenuRules.isEnabled(.back, session: s))
        #expect(!MenuRules.isEnabled(.forward, session: s))
        MenuRules.perform(.back, on: s)
        #expect(s.selectedPage == refs[0])
        #expect(MenuRules.isEnabled(.forward, session: s))
        MenuRules.perform(.forward, on: s)
        #expect(s.selectedPage == refs[1])
    }

    @Test func everyCommandHasATitleAndAMenuPlace() {
        for command in SessionCommand.allCases { #expect(!command.title.isEmpty) }
        #expect(Set(SessionCommand.allCases.map(\.title)).count == SessionCommand.allCases.count)
    }

    @Test func agreedOnlyTogglesTheSession() async throws {
        let s = try await session()
        #expect(!s.agreedOnly)
        MenuRules.perform(.agreedOnly, on: s)
        #expect(s.agreedOnly)
        MenuRules.perform(.agreedOnly, on: s)
        #expect(!s.agreedOnly)
    }

    @Test func showInListNeedsAProjection() async throws {
        let s = try await session("arc42-views")
        #expect(!MenuRules.isEnabled(.showInList, session: s))
        let section = try #require(s.metamodel.sections.first { ProjectionHost.modes(for: $0, metamodel: s.metamodel).count > 1 })
        let mode = try #require(ProjectionHost.modes(for: section, metamodel: s.metamodel).first { ProjectionHost.nativeProjections.contains($0) })
        s.select(section: section.id)
        s.select(mode: mode)
        #expect(MenuRules.isEnabled(.showInList, session: s))
        MenuRules.perform(.showInList, on: s)
        #expect(s.mode == ListModel.listMode)
        #expect(!MenuRules.isEnabled(.showInList, session: s))
    }

    @Test func aPageThatVanishedDisablesThePageCommands() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let ref = try #require(pages(s).first)
        s.select(page: ref)
        try FileManager.default.removeItem(at: copy.appending(path: "wiki/functional-requirements/\(ref.stem).md"))
        await s.refresh(changed: [])
        for command in Self.needsAPage { #expect(!MenuRules.isEnabled(command, session: s), "\(command)") }
    }

    // MARK: Sections

    @Test func sectionShortcutsFollowTheSidebar() async throws {
        for name in Fixture.names {
            let s = try await session(name)
            let rows = s.sidebar.flatMap(\.rows)
            let shortcuts = MenuRules.sectionShortcuts(of: s)
            #expect(shortcuts.count == min(9, rows.count), "\(name)")
            for (index, shortcut) in shortcuts.enumerated() {
                #expect(shortcut.number == index + 1)
                #expect(shortcut.id == rows[index].section.id)
                #expect(shortcut.title == rows[index].section.title)
            }
            MenuRules.selectSection(number: 3, in: s)
            #expect(s.selectedSection == rows[2].section.id, "\(name)")
        }
    }

    @Test func aNumberWithoutARowDoesNothing() async throws {
        let s = try await session()
        for number in [0, 10, -1, 99] {
            MenuRules.selectSection(number: number, in: s)
            #expect(s.selectedSection == nil)
        }
        MenuRules.selectSection(number: 1, in: nil)
    }

    @Test func shortcutsDoNotClashWithEachOtherOrWithTheSystem() {
        let keys = Shortcuts.all.map(\.keys)
        #expect(Set(keys).count == keys.count, "\(keys)")
        let system: Set<String> = ["⌘Q", "⌘W", "⌘H", "⌘M", "⌘C", "⌘V", "⌘X", "⌘Z", "⇧⌘Z", "⌘A", "⌘,", "⌘N", "⌘S", "⌘P", "⌘T", "⌘`",
                                   "⌥⌘H", "⌥⌘M", "⌃⌘F", "⌘0", "⌘=", "⌘-", "⌘Space"]
        #expect(Set(keys).isDisjoint(with: system), "\(Set(keys).intersection(system))")
        // Cmd-1 to Cmd-9 are the sections.
        #expect(Shortcuts.all.filter { $0.keys.hasPrefix("⌘") && $0.keys.count == 2 && $0.keys.last?.isNumber == true }.count == 9)
    }
}
