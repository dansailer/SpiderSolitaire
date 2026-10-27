/// The whole menu bar as data (SPEC.md §3.5). The app builds its `NSMenu`s from this once, at
/// launch, and never rebuilds or edits them afterwards, so nothing can appear and disappear.
/// Enabled and checked states come from AppKit's menu item validation, which runs only when a
/// menu opens or a shortcut is pressed.
public enum MenuBarLayout {
    /// An item macOS implements: AppKit sends `selector` through the responder chain.
    public struct StandardItem: Hashable, Sendable {
        public let title: String
        public let selector: String
        public let shortcut: MenuShortcut?

        public init(_ title: String, selector: String, shortcut: MenuShortcut? = nil) {
            self.title = title
            self.selector = selector
            self.shortcut = shortcut
        }
    }

    public indirect enum Entry: Hashable, Sendable {
        /// An app command from `MenuCommand`.
        case command(MenuCommand)
        case standard(StandardItem)
        /// About and Settings…: app actions with the standard titles.
        case app(AppItem)
        /// The Services submenu, filled in by macOS.
        case services
        case submenu(MenuCommand.Menu, [Entry])
        case separator
    }

    public enum AppItem: String, Hashable, Sendable, CaseIterable {
        case about, settings

        public var title: String {
            switch self {
            case .about: return "About Spider Solitaire"
            case .settings: return "Settings…"
            }
        }

        public var shortcut: MenuShortcut? { self == .settings ? MenuShortcut(",") : nil }
    }

    /// Which `NSApplication` slot a top menu fills (Window and Help get macOS's extras: the window
    /// list, and the Help search field).
    public enum Role: Hashable, Sendable {
        case app, game, window, help
    }

    public struct TopMenu: Hashable, Sendable {
        public let title: String
        public let role: Role
        public let entries: [Entry]
    }

    public static let menuBar: [TopMenu] = [
        TopMenu(title: MenuCommand.Menu.app.rawValue, role: .app, entries: [
            .app(.about),
            .separator,
            .app(.settings),
            .separator,
            .services,
            .separator,
            .standard(StandardItem("Hide Spider Solitaire", selector: "hide:", shortcut: MenuShortcut("h"))),
            .standard(StandardItem("Hide Others", selector: "hideOtherApplications:",
                                   shortcut: MenuShortcut("h", option: true))),
            .standard(StandardItem("Show All", selector: "unhideAllApplications:")),
            .separator,
            .standard(StandardItem("Quit Spider Solitaire", selector: "terminate:", shortcut: MenuShortcut("q"))),
        ]),
        TopMenu(title: MenuCommand.Menu.game.rawValue, role: .game, entries: [
            .command(.newGame), .command(.restartGame),
            .separator,
            .command(.undo), .command(.redo),
            .separator,
            .command(.dealNextRow), .command(.showHint),
            .separator,
            .submenu(.difficulty, [.command(.oneSuit), .command(.twoSuits), .command(.fourSuits)]),
            .separator,
            .command(.statistics), .command(.achievements),
            .separator,
            .command(.saveGame), .command(.openSavedGame),
            .separator,
            .command(.closeWindow),
        ]),
        TopMenu(title: MenuCommand.Menu.window.rawValue, role: .window, entries: [
            .standard(StandardItem("Minimize", selector: "performMiniaturize:", shortcut: MenuShortcut("m"))),
            .standard(StandardItem("Zoom", selector: "performZoom:")),
            .separator,
            .command(.enterFullScreen),
            .separator,
            .standard(StandardItem("Bring All to Front", selector: "arrangeInFront:")),
            // macOS appends the list of open windows below.
        ]),
        TopMenu(title: MenuCommand.Menu.help.rawValue, role: .help, entries: [
            .command(.help),
        ]),
    ]

    /// Every entry of `menu`, submenus included, in menu order.
    public static func flatten(_ entries: [Entry]) -> [Entry] {
        entries.flatMap { (entry: Entry) -> [Entry] in
            if case .submenu(_, let children) = entry { return [entry] + flatten(children) }
            return [entry]
        }
    }

    /// The app commands in the bar, in order.
    public static var commands: [MenuCommand] {
        menuBar.flatMap { flatten($0.entries) }.compactMap { (entry: Entry) -> MenuCommand? in
            if case .command(let command) = entry { return command }
            return nil
        }
    }

    /// Every shortcut in the bar with the title of its item.
    public static var shortcuts: [(MenuShortcut, String)] {
        menuBar.flatMap { flatten($0.entries) }.compactMap { (entry: Entry) -> (MenuShortcut, String)? in
            switch entry {
            case .command(let c): return c.shortcut.map { ($0, c.title) }
            case .standard(let s): return s.shortcut.map { ($0, s.title) }
            case .app(let a): return a.shortcut.map { ($0, a.title) }
            default: return nil
            }
        }
    }
}

extension MenuCommand {
    /// Commands that are AppKit's own actions, sent through the responder chain instead of to the
    /// app. AppKit retitles a `toggleFullScreen:` item to Enter / Exit Full Screen by itself.
    public var standardSelector: String? {
        self == .enterFullScreen ? "toggleFullScreen:" : nil
    }
}
