import XCTest

@testable import SpiderBoard

final class MenuBarLayoutTests: XCTestCase {
    func testExactlyAppGameWindowHelp() {
        XCTAssertEqual(MenuBarLayout.menuBar.map(\.title), ["Spider Solitaire", "Game", "Window", "Help"])
        XCTAssertEqual(MenuBarLayout.menuBar.map(\.role), [.app, .game, .window, .help])
        for banned in ["File", "Edit", "View", "Format"] {
            XCTAssertFalse(MenuBarLayout.menuBar.contains { $0.title == banned }, banned)
        }
    }

    func testEveryCommandAppearsExactlyOnceInItsMenu() {
        XCTAssertEqual(
            MenuBarLayout.commands.sorted { $0.rawValue < $1.rawValue },
            MenuCommand.allCases.sorted { $0.rawValue < $1.rawValue })
        for top in MenuBarLayout.menuBar {
            for entry in top.entries {
                switch entry {
                case .command(let c):
                    XCTAssertEqual(c.menu.rawValue, top.title, "\(c)")
                case .submenu(let menu, let children):
                    for case .command(let c) in children { XCTAssertEqual(c.menu, menu, "\(c)") }
                default: break
                }
            }
        }
    }

    func testFullScreenOnceInWindowMenuAsAppKitsOwnAction() {
        let window = MenuBarLayout.menuBar.first { $0.role == .window }!
        let fullScreen = MenuBarLayout.flatten(window.entries).filter {
            if case .command(.enterFullScreen) = $0 { return true }
            return false
        }
        XCTAssertEqual(fullScreen.count, 1)
        XCTAssertEqual(MenuCommand.enterFullScreen.standardSelector, "toggleFullScreen:")
        XCTAssertEqual(MenuCommand.enterFullScreen.shortcut?.description, "⌃⌘F")
        let others = MenuBarLayout.menuBar.filter { $0.role != .window }.flatMap { MenuBarLayout.flatten($0.entries) }
        XCTAssertFalse(others.contains(.command(.enterFullScreen)))
        XCTAssertEqual(MenuCommand.allCases.filter { $0.standardSelector != nil }, [.enterFullScreen])
    }

    func testShortcutsAreUniqueAcrossTheBar() {
        let keys = MenuBarLayout.shortcuts.map(\.0)
        XCTAssertEqual(Set(keys).count, keys.count, "\(MenuBarLayout.shortcuts)")
        // The standard items use the shortcuts the reserved table names.
        for (shortcut, title) in MenuBarLayout.shortcuts where MenuCommand.allCases.allSatisfy({ $0.title != title }) {
            XCTAssertEqual(MenuCommand.reservedShortcuts[shortcut], title)
        }
    }

    func testGameMenuShortcutsUnchanged() {
        let game = MenuBarLayout.shortcuts.filter { pair in MenuCommand.items(in: .game).contains { $0.title == pair.1 }
        }
        XCTAssertEqual(
            game.map { "\($0.0) \($0.1)" },
            [
                "⌘N New Game", "⇧⌘N Restart Game", "⌘Z Undo", "⇧⌘Z Redo", "⌘D Deal Next Row", "⌘T Show Hint",
                "⌘I Statistics…", "⇧⌘A Achievements…", "⌘S Save Game", "⌘O Open Saved Game", "⌘W Close Window",
            ])
    }

    func testAppAndHelpMenuOrder() {
        XCTAssertEqual(
            Array(MenuBarLayout.menuBar[0].entries.prefix(3)), [.app(.about), .command(.checkForUpdates), .separator])
        XCTAssertEqual(MenuBarLayout.menuBar[3].entries, [.command(.help), .separator, .command(.visitWebsite)])
    }

    func testNoEmptyMenusOrDoubledSeparators() {
        for top in MenuBarLayout.menuBar {
            XCTAssertFalse(top.entries.isEmpty)
            XCTAssertNotEqual(top.entries.first, .separator)
            XCTAssertNotEqual(top.entries.last, .separator)
            for (a, b) in zip(top.entries, top.entries.dropFirst()) {
                XCTAssertFalse(a == .separator && b == .separator, top.title)
            }
        }
    }
}
