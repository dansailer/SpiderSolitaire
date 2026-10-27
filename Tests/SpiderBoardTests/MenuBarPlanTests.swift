import XCTest
@testable import SpiderBoard

final class MenuBarPlanTests: XCTestCase {
    typealias Top = MenuBarPlan.TopMenu
    let file = Top(shortcuts: [MenuShortcut("w")])
    let edit = Top(shortcuts: [MenuShortcut("z"), MenuShortcut("c")])
    let view = Top(shortcuts: [MenuShortcut("f", control: true)])
    let game = Top(shortcuts: [MenuShortcut("n"), MenuShortcut("z"), MenuShortcut("d")])
    let window = Top(isWindowsMenu: true, shortcuts: [MenuShortcut("m")])
    let help = Top(isHelpMenu: true, shortcuts: [MenuShortcut("?")])

    func testRemovesEverythingButGameWindowAndHelp() {
        let bar = [file, edit, view, game, window, help]
        XCTAssertEqual(MenuBarPlan.menusToRemove(bar), [2, 1, 0])
    }

    func testIsIdempotent() {
        var bar = [file, edit, view, game, window, help]
        for i in MenuBarPlan.menusToRemove(bar) { bar.remove(at: i) }
        XCTAssertEqual(bar, [game, window, help])
        XCTAssertEqual(MenuBarPlan.menusToRemove(bar), [], "a clean bar needs no change")
        XCTAssertNil(MenuBarPlan.helpMenuToAdopt(bar))
    }

    func testTouchesNothingBeforeTheGameMenuExists() {
        XCTAssertEqual(MenuBarPlan.menusToRemove([file, edit, view, window, help]), [])
    }

    func testKeepsTheHelpItemsMenuEvenIfAppKitDoesNotKnowIt() {
        let unknownHelp = Top(shortcuts: [MenuShortcut("?")])
        let bar = [edit, game, window, unknownHelp]
        XCTAssertEqual(MenuBarPlan.menusToRemove(bar), [0])
        XCTAssertEqual(MenuBarPlan.helpMenuToAdopt(bar), 3)
    }

    func testEmptyMenusGo() {
        XCTAssertEqual(MenuBarPlan.menusToRemove([Top(), game, window, help]), [0])
    }

    func testOnlyTabItemsLeaveTheWindowMenu() {
        let actions: [String?] = ["performMiniaturize:", "performZoom:", nil, "toggleTabBar:", "toggleFullScreen:",
                                  "mergeAllWindows:", "arrangeInFront:"]
        XCTAssertEqual(MenuBarPlan.windowItemsToRemove(actions: actions), [5, 3])
        XCTAssertEqual(MenuBarPlan.windowItemsToRemove(actions: ["performZoom:", "toggleFullScreen:"]), [],
                       "Full Screen is AppKit's and stays where AppKit put it")
    }
}
