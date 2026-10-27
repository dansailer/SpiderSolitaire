#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore

/// Builds the menu bar from `MenuBarLayout` (SPEC.md §3.5), once, at launch. The app owns
/// `NSApp.mainMenu` outright: there are no SwiftUI `Commands`, so nothing ever inserts File,
/// Edit, View or Format menus, and nothing rebuilds the bar when the game changes. Enabled and
/// checked states come from `validateMenuItem(_:)`, which AppKit calls only when a menu opens or
/// a shortcut is pressed.
@MainActor
enum MainMenuBuilder {
    /// Before the menu exists: no window tabs, no automatic Full Screen item (the Window menu has
    /// its own), and no Start Dictation / Emoji & Symbols items.
    static func prepare() {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.register(defaults: [
            // AppKit's own Full Screen item would be a second one in the Window menu.
            "NSFullScreenMenuItemEverywhere": false,
            "NSDisabledDictationMenuItem": true,
            "NSDisabledCharacterPaletteMenuItem": true,
        ])
    }

    static func install(target: MenuController) {
        let app: NSApplication = NSApplication.shared
        let bar: NSMenu = NSMenu(title: "Main Menu")
        for top in MenuBarLayout.menuBar {
            let menu: NSMenu = NSMenu(title: top.title)
            for entry in top.entries {
                menu.addItem(item(for: entry, target: target, app: app))
            }
            let holder: NSMenuItem = NSMenuItem(title: top.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            bar.addItem(holder)
            switch top.role {
            case .app, .game: break
            case .window: app.windowsMenu = menu
            case .help: app.helpMenu = menu
            }
        }
        app.mainMenu = bar
    }

    private static func item(for entry: MenuBarLayout.Entry, target: MenuController, app: NSApplication) -> NSMenuItem {
        switch entry {
        case .separator:
            return NSMenuItem.separator()
        case .services:
            let item: NSMenuItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            let services: NSMenu = NSMenu(title: "Services")
            item.submenu = services
            app.servicesMenu = services
            return item
        case .submenu(let menu, let children):
            let item: NSMenuItem = NSMenuItem(title: menu.rawValue, action: nil, keyEquivalent: "")
            let sub: NSMenu = NSMenu(title: menu.rawValue)
            for child in children { sub.addItem(self.item(for: child, target: target, app: app)) }
            item.submenu = sub
            return item
        case .standard(let standard):
            // No target: AppKit sends it to the key window or the application.
            return make(standard.title, selector: Selector(standard.selector), shortcut: standard.shortcut, target: nil)
        case .app(let appItem):
            let item: NSMenuItem = make(appItem.title, selector: #selector(MenuController.performAppItem(_:)),
                                        shortcut: appItem.shortcut, target: target)
            item.representedObject = appItem.rawValue
            return item
        case .command(let command):
            if let selector: String = command.standardSelector {
                return make(command.title, selector: Selector(selector), shortcut: command.shortcut, target: nil)
            }
            let item: NSMenuItem = make(command.title, selector: #selector(MenuController.performCommand(_:)),
                                        shortcut: command.shortcut, target: target)
            item.representedObject = command.rawValue
            return item
        }
    }

    private static func make(_ title: String, selector: Selector, shortcut: MenuShortcut?, target: AnyObject?) -> NSMenuItem {
        let item: NSMenuItem = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target
        if let shortcut {
            item.keyEquivalent = String(shortcut.key)
            var mask: NSEvent.ModifierFlags = []
            if shortcut.command { mask.insert(NSEvent.ModifierFlags.command) }
            if shortcut.shift { mask.insert(NSEvent.ModifierFlags.shift) }
            if shortcut.option { mask.insert(NSEvent.ModifierFlags.option) }
            if shortcut.control { mask.insert(NSEvent.ModifierFlags.control) }
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    /// The top-level titles and the Window menu's titles (for the `--menu-probe` check).
    /// On macOS 15 and later AppKit adds its own visible Enter Full Screen item (shortcut 🌐F) next
    /// to ours and hides ours, which keeps ⌃⌘F working: the menu still shows the item once.
    static func snapshot() -> String {
        let app: NSApplication = NSApplication.shared
        let tops: [String] = app.mainMenu?.items.map { (item: NSMenuItem) -> String in item.title } ?? []
        let window: [String] = app.windowsMenu?.items.map { (item: NSMenuItem) -> String in
            // Hidden items (AppKit hides ours when it adds its own 🌐F one) are marked.
            item.isSeparatorItem ? "-" : item.title + (item.isHidden ? "[hidden]" : "")
        } ?? []
        return tops.joined(separator: "|") + " :: Window=" + window.joined(separator: "|")
    }
}

/// The target of every app menu item: performs the command and answers validation from the
/// model's current state.
@MainActor
final class MenuController: NSObject, NSMenuItemValidation {
    private let model: GameModel
    private let windows: WindowController

    init(model: GameModel, windows: WindowController) {
        self.model = model
        self.windows = windows
    }

    @objc func performAppItem(_ sender: NSMenuItem) {
        guard let raw: String = sender.representedObject as? String,
              let item: MenuBarLayout.AppItem = MenuBarLayout.AppItem(rawValue: raw) else { return }
        switch item {
        case .about: AboutPanel.show()
        case .settings: windows.showSettings()
        }
    }

    @objc func performCommand(_ sender: NSMenuItem) {
        guard let raw: String = sender.representedObject as? String,
              let command: MenuCommand = MenuCommand(rawValue: raw) else { return }
        perform(command)
    }

    func perform(_ command: MenuCommand) {
        switch command {
        case .newGame: model.requestNewGame(nil)
        case .restartGame: model.requestRestart()
        case .undo: model.undo()
        case .redo: model.redo()
        case .dealNextRow: model.deal()
        case .showHint: model.showHint()
        case .oneSuit: model.requestNewGame(Difficulty.oneSuit)
        case .twoSuits: model.requestNewGame(Difficulty.twoSuits)
        case .fourSuits: model.requestNewGame(Difficulty.fourSuits)
        case .statistics:
            windows.showBoard()
            model.showStatisticsSheet = true
        case .achievements: windows.showAchievements()
        case .saveGame: model.saveGame()
        case .openSavedGame: model.requestOpenSavedGame()
        case .closeWindow: NSApplication.shared.keyWindow?.performClose(nil)
        case .enterFullScreen: windows.showBoard() // normally AppKit's toggleFullScreen: (standardSelector)
        case .help: windows.showHelp()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let raw: String = menuItem.representedObject as? String,
              let command: MenuCommand = MenuCommand(rawValue: raw) else { return true }
        switch command {
        case .undo: return model.canUndo
        case .redo: return model.canRedo
        case .openSavedGame: return model.hasSavedGame
        case .closeWindow: return NSApplication.shared.keyWindow != nil
        case .oneSuit, .twoSuits, .fourSuits:
            let difficulty: Difficulty = command == .oneSuit ? .oneSuit : (command == .twoSuits ? .twoSuits : .fourSuits)
            menuItem.state = model.game.state.difficulty == difficulty ? NSControl.StateValue.on : NSControl.StateValue.off
            return true
        default: return true
        }
    }
}

/// Spider Solitaire ▸ About Spider Solitaire: the standard panel (name and version from
/// Info.plist) with the card art credits.
enum AboutPanel {
    static let creditsText: String = """
        Classic card faces: "English pattern" playing cards by Dmitry Fomin (CC0 1.0).
        Ornate ace of spades: Byron Knoll, vector-playing-cards (public domain).
        Sounds are the built-in macOS system sounds.
        """

    @MainActor
    static func show() {
        let style: NSMutableParagraphStyle = NSMutableParagraphStyle()
        style.alignment = NSTextAlignment.center
        let credits: NSAttributedString = NSAttributedString(string: creditsText, attributes: [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor,
            NSAttributedString.Key.paragraphStyle: style,
        ])
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            NSApplication.AboutPanelOptionKey.applicationName: "Spider Solitaire",
            NSApplication.AboutPanelOptionKey.credits: credits,
        ]
        // Running unbundled (swift run) there is no version in Info.plist.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") == nil {
            options[NSApplication.AboutPanelOptionKey.applicationVersion] = "development build"
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
}
#endif
