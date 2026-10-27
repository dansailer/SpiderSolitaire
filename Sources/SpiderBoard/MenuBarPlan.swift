/// What `MainMenuCleaner` (in the app) should change in the menu bar, decided from a plain
/// description of it so the rules are testable without AppKit. Menus are identified by structure,
/// never by title, so this works in every language.
public enum MenuBarPlan {
    /// One top-level menu after the app menu.
    public struct TopMenu: Hashable, Sendable {
        /// It is `NSApp.windowsMenu`.
        public var isWindowsMenu: Bool
        /// It is `NSApp.helpMenu`.
        public var isHelpMenu: Bool
        /// Key equivalents of its items (and their submenus).
        public var shortcuts: [MenuShortcut]

        public init(isWindowsMenu: Bool = false, isHelpMenu: Bool = false, shortcuts: [MenuShortcut] = []) {
            self.isWindowsMenu = isWindowsMenu
            self.isHelpMenu = isHelpMenu
            self.shortcuts = shortcuts
        }

        /// The Game menu holds New Game (⌘N).
        public var isGameMenu: Bool { MenuCommand.newGame.shortcut.map(shortcuts.contains) ?? false }
        /// The Help menu holds Spider Solitaire Help (⌘?), even if AppKit doesn't know it as such.
        public var holdsHelp: Bool { MenuCommand.help.shortcut.map(shortcuts.contains) ?? false }
        public var isKept: Bool { isWindowsMenu || isHelpMenu || isGameMenu || holdsHelp }
    }

    /// Indexes (into `menus`) to remove, highest first. Empty when the Game menu isn't there yet
    /// (SwiftUI hasn't built the bar), so a half-built bar is never touched.
    public static func menusToRemove(_ menus: [TopMenu]) -> [Int] {
        guard menus.contains(where: \.isGameMenu) else { return [] }
        return menus.indices.filter { !menus[$0].isKept }.reversed()
    }

    /// The menu that should be `NSApp.helpMenu` (so macOS adds the search field), if it isn't yet.
    public static func helpMenuToAdopt(_ menus: [TopMenu]) -> Int? {
        guard !menus.contains(where: \.isHelpMenu) else { return nil }
        return menus.firstIndex(where: \.holdsHelp)
    }

    /// Window-tab actions (none appear with tabbing off; dropped if they ever do).
    public static let tabActions: Set<String> = [
        "toggleTabBar:", "toggleTabOverview:", "mergeAllWindows:", "moveTabToNewWindow:",
        "selectNextTab:", "selectPreviousTab:",
    ]

    /// Indexes of Window-menu items to remove, highest first.
    public static func windowItemsToRemove(actions: [String?]) -> [Int] {
        actions.indices.filter { actions[$0].map(tabActions.contains) ?? false }.reversed()
    }
}
