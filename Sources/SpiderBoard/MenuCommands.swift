import SpiderCore

/// A menu key equivalent: a key plus modifiers (⌃ ⌥ ⇧ ⌘).
public struct MenuShortcut: Hashable, Sendable, CustomStringConvertible {
    public let key: Character
    public var command = true
    public var shift = false
    public var option = false
    public var control = false

    public init(
        _ key: Character, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// As macOS menus show it, modifiers in ⌃⌥⇧⌘ order.
    public var description: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
            + String(key).uppercased()
    }
}

/// Every menu item the app defines, with its title and shortcut. The SwiftUI menus are built from
/// this table, and tests check it against `MenuCommand.reservedShortcuts`. Items that macOS or
/// SwiftUI provide themselves (About, Settings…, Services, Hide, Quit, Minimize, Zoom) are listed
/// as reserved, not here.
public enum MenuCommand: String, CaseIterable, Sendable {
    case newGame, restartGame
    case undo, redo
    case dealNextRow, showHint
    case oneSuit, twoSuits, fourSuits
    case statistics, achievements
    case saveGame, openSavedGame
    case closeWindow
    case enterFullScreen
    case help, visitWebsite
    case checkForUpdates

    public enum Menu: String, Sendable {
        case app = "Spider Solitaire", game = "Game", difficulty = "Difficulty", window = "Window", help = "Help"
    }

    public var title: String {
        switch self {
        case .newGame: return "New Game"
        case .restartGame: return "Restart Game"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .dealNextRow: return "Deal Next Row"
        case .showHint: return "Show Hint"
        case .oneSuit: return "One Suit"
        case .twoSuits: return "Two Suits"
        case .fourSuits: return "Four Suits"
        case .statistics: return "Statistics…"
        case .achievements: return "Achievements…"
        case .saveGame: return "Save Game"
        case .openSavedGame: return "Open Saved Game"
        case .closeWindow: return "Close Window"
        case .enterFullScreen: return "Enter Full Screen"
        case .help: return "Spider Solitaire Help"
        case .visitWebsite: return "Visit Website"
        case .checkForUpdates: return "Check for Updates…"
        }
    }

    public var menu: Menu {
        switch self {
        case .oneSuit, .twoSuits, .fourSuits: return .difficulty
        case .enterFullScreen: return .window
        case .help, .visitWebsite: return .help
        case .checkForUpdates: return .app
        default: return .game
        }
    }

    public var shortcut: MenuShortcut? {
        switch self {
        case .newGame: return MenuShortcut("n")
        case .restartGame: return MenuShortcut("n", shift: true)
        case .undo: return MenuShortcut("z")
        case .redo: return MenuShortcut("z", shift: true)
        case .dealNextRow: return MenuShortcut("d")
        // ⌘H is Hide and ⌘M Minimize, so the hint ("tip") gets ⌘T: its standard meanings (Show
        // Fonts, New Tab) don't exist here, since there is no Format menu and tabs are off.
        case .showHint: return MenuShortcut("t")
        case .oneSuit: return MenuShortcut("1")
        case .twoSuits: return MenuShortcut("2")
        case .fourSuits: return MenuShortcut("4")
        // ⌘I is Get Info in Finder (and Italic in text apps, which this is not).
        case .statistics: return MenuShortcut("i")
        case .achievements: return MenuShortcut("a", shift: true)
        case .saveGame: return MenuShortcut("s")
        case .openSavedGame: return MenuShortcut("o")
        case .closeWindow: return MenuShortcut("w")
        // AppKit adds and places its own toggleFullScreen: item in the Window menu; the app never
        // creates or moves it. Listed so the table (and the help) show the whole menu bar.
        case .enterFullScreen: return MenuShortcut("f", control: true)
        // The standard Help shortcut (⇧⌘/ on most keyboards).
        case .help: return MenuShortcut("?")
        case .visitWebsite, .checkForUpdates: return nil
        }
    }

    /// Commands shown in `menu`, in menu order.
    public static func items(in menu: Menu) -> [MenuCommand] { allCases.filter { $0.menu == menu } }

    /// Shortcuts that macOS, the app menu or the Window menu already use, or that the system
    /// keeps for itself (HIG "Keyboard shortcuts" and macOS system shortcuts). App commands must
    /// not reuse them.
    public static let reservedShortcuts: [MenuShortcut: String] = [
        MenuShortcut(","): "Settings…",
        MenuShortcut("h"): "Hide Spider Solitaire",
        MenuShortcut("h", option: true): "Hide Others",
        MenuShortcut("q"): "Quit Spider Solitaire",
        MenuShortcut("q", option: true): "Quit and Keep Windows",
        MenuShortcut("m"): "Minimize",
        MenuShortcut("m", option: true): "Minimize All",
        MenuShortcut("`"): "Cycle Through Windows",
        MenuShortcut("?"): "Spider Solitaire Help",
        MenuShortcut("/", shift: true): "Spider Solitaire Help",
        MenuShortcut(" "): "Spotlight",
        MenuShortcut(" ", control: true): "Emoji & Symbols / input sources",
        MenuShortcut("\t"): "App Switcher",
        MenuShortcut("3", shift: true): "Screenshot",
        MenuShortcut("4", shift: true): "Screenshot of a selection",
        MenuShortcut("5", shift: true): "Screenshot and recording options",
        MenuShortcut("q", control: true): "Lock Screen",
        MenuShortcut("d", option: true): "Show or hide the Dock",
        MenuShortcut("\u{1B}", option: true): "Force Quit",
        MenuShortcut("f", control: true): "Enter Full Screen",
        MenuShortcut("."): "Cancel",
        MenuShortcut("c"): "Copy",
        MenuShortcut("v"): "Paste",
        MenuShortcut("x"): "Cut",
        MenuShortcut("a"): "Select All",
        MenuShortcut("p"): "Print",
        MenuShortcut("f"): "Find",
    ]
}
