import XCTest

@testable import SpiderBoard

final class MenuCommandTests: XCTestCase {
    func testShortcutsAreUnique() {
        let shortcuts = MenuCommand.allCases.compactMap(\.shortcut)
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
    }

    func testNoAppCommandUsesAReservedShortcut() {
        // Full Screen and Help are the standard items themselves.
        for command in MenuCommand.allCases where command != .enterFullScreen && command != .help {
            guard let shortcut = command.shortcut else { continue }
            XCTAssertNil(
                MenuCommand.reservedShortcuts[shortcut],
                "\(command) \(shortcut) clashes with \(MenuCommand.reservedShortcuts[shortcut] ?? "")")
        }
        XCTAssertEqual(MenuCommand.reservedShortcuts[MenuCommand.enterFullScreen.shortcut!], "Enter Full Screen")
        XCTAssertEqual(MenuCommand.reservedShortcuts[MenuCommand.help.shortcut!], MenuCommand.help.title)
    }

    func testEveryShortcutUsesCommandOrControl() {
        for command in MenuCommand.allCases {
            guard let s = command.shortcut else { continue }
            XCTAssertTrue(s.command || s.control, "\(command): no bare-key shortcuts")
        }
    }

    func testTitlesAreTitleCaseWithEllipsesOnlyForDialogs() {
        let minor: Set<String> = ["a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "at", "by"]
        for command in MenuCommand.allCases {
            let title = command.title
            let words = title.replacingOccurrences(of: "…", with: "").split(separator: " ").map(String.init)
            for (i, word) in words.enumerated() where i == 0 || !minor.contains(word.lowercased()) {
                XCTAssertEqual(word.first.map { String($0).uppercased() }, word.first.map(String.init), "\(title)")
            }
            XCTAssertFalse(title.hasSuffix("..."), "use the ellipsis character")
            let opensDialog = [MenuCommand.statistics, .achievements, .checkForUpdates].contains(command)
            XCTAssertEqual(title.hasSuffix("…"), opensDialog, title)
        }
    }

    func testMenusAndDisplay() {
        XCTAssertEqual(MenuCommand.items(in: .difficulty), [.oneSuit, .twoSuits, .fourSuits])
        XCTAssertEqual(MenuCommand.items(in: .window), [.enterFullScreen])
        XCTAssertEqual(MenuCommand.items(in: .help), [.help, .visitWebsite])
        XCTAssertEqual(MenuCommand.items(in: .app), [.checkForUpdates])
        XCTAssertNil(MenuCommand.visitWebsite.shortcut)
        XCTAssertNil(MenuCommand.checkForUpdates.shortcut)
        XCTAssertFalse(MenuCommand.items(in: .game).contains(.oneSuit))
        XCTAssertEqual(MenuCommand.redo.shortcut?.description, "⇧⌘Z")
        XCTAssertEqual(MenuCommand.enterFullScreen.shortcut?.description, "⌃⌘F")
        XCTAssertEqual(MenuCommand.achievements.shortcut?.description, "⇧⌘A")
    }
}
