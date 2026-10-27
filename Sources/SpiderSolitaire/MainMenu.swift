#if canImport(SwiftUI)
import AppKit
import SpiderBoard

/// Final touches SwiftUI's `Commands` can't express (SPEC.md §3.5):
/// - the menu bar is exactly: app menu, Game, Window, Help. Any other menu SwiftUI or AppKit
///   inserts (File, Edit, View, Format), even with all its groups replaced, is removed. Menus are
///   identified structurally (position 0, `NSApp.windowsMenu`, `NSApp.helpMenu`, and the Game menu
///   as the one holding ⌘N), never by title, so this works in every language;
/// - AppKit's Enter Full Screen item (`toggleFullScreen:`, ⌃⌘F) moves to the Window menu, after
///   Zoom, where AppKit keeps its title (Enter / Exit Full Screen) up to date;
/// - window-tab items are dropped.
/// SwiftUI may rebuild menus when commands change, so this runs again (coalesced) whenever a menu
/// gains an item. Every step is idempotent, and nothing is removed if the Game menu isn't found.
@MainActor
final class MainMenuCleaner {
    static let shared: MainMenuCleaner = MainMenuCleaner()

    /// Before any window or menu exists: no window tabs, and no Start Dictation / Emoji & Symbols
    /// items (AppKit adds them to whatever menu it thinks is Edit).
    static func prepare() {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
    }

    /// Window-tab actions (gone anyway with tabbing off).
    static let tabActions: Set<String> = [
        "toggleTabBar:", "toggleTabOverview:", "mergeAllWindows:", "moveTabToNewWindow:",
        "selectNextTab:", "selectPreviousTab:",
    ]

    static let fullScreenAction: Selector = #selector(NSWindow.toggleFullScreen(_:))
    static let zoomAction: Selector = #selector(NSWindow.performZoom(_:))

    private var observer: NSObjectProtocol? = nil
    private var pending: Bool = false
    private var cleaning: Bool = false

    func start() {
        clean()
        // Again once SwiftUI has finished its first menu pass.
        Task { @MainActor [weak self] in self?.clean() }
        observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification, object: nil, queue: OperationQueue.main
        ) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.scheduleClean() }
        }
    }

    private func scheduleClean() {
        guard !cleaning, !pending else { return }
        pending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pending = false
            self.clean()
        }
    }

    /// Items of `menu` and of its submenus.
    private static func allItems(_ menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        return menu.items.flatMap { (item: NSMenuItem) -> [NSMenuItem] in [item] + allItems(item.submenu) }
    }

    private static func actionName(_ item: NSMenuItem) -> String? {
        item.action.map { (selector: Selector) -> String in NSStringFromSelector(selector) }
    }

    /// The Game menu: the one holding ⌘N. Never removed, whatever its items' actions.
    private static func isGameMenu(_ menu: NSMenu) -> Bool {
        guard let newGame: MenuShortcut = MenuCommand.newGame.shortcut else { return false }
        return menu.items.contains { (item: NSMenuItem) -> Bool in
            item.keyEquivalent == String(newGame.key)
                && item.keyEquivalentModifierMask.intersection(NSEvent.ModifierFlags.deviceIndependentFlagsMask)
                    == NSEvent.ModifierFlags.command
        }
    }

    func clean() {
        guard !cleaning, let mainMenu: NSMenu = NSApplication.shared.mainMenu else { return }
        cleaning = true
        defer { cleaning = false }

        let windowsMenu: NSMenu? = NSApplication.shared.windowsMenu
        let helpMenu: NSMenu? = NSApplication.shared.helpMenu
        var fullScreenItems: [NSMenuItem] = []

        let topItems: [NSMenuItem] = Array(mainMenu.items.dropFirst())
        guard topItems.contains(where: { (item: NSMenuItem) -> Bool in
            item.submenu.map(MainMenuCleaner.isGameMenu) ?? false
        }) else { return }

        // Everything after the app menu (index 0) that is not Game, Window or Help goes.
        for topItem in topItems.reversed() {
            if let menu: NSMenu = topItem.submenu,
               menu === windowsMenu || menu === helpMenu || MainMenuCleaner.isGameMenu(menu) { continue }
            for item in MainMenuCleaner.allItems(topItem.submenu) where item.action == MainMenuCleaner.fullScreenAction {
                item.menu?.removeItem(item)
                fullScreenItems.append(item)
            }
            mainMenu.removeItem(topItem)
        }

        guard let windowsMenu else { return }
        for item in windowsMenu.items {
            if let name: String = MainMenuCleaner.actionName(item), MainMenuCleaner.tabActions.contains(name) {
                windowsMenu.removeItem(item)
            }
        }
        // Exactly one Enter Full Screen, in the Window menu after Zoom.
        let existing: [NSMenuItem] = windowsMenu.items.filter { (item: NSMenuItem) -> Bool in
            item.action == MainMenuCleaner.fullScreenAction
        }
        for extra in existing.dropFirst() { windowsMenu.removeItem(extra) }
        guard existing.isEmpty else { return }
        let item: NSMenuItem = fullScreenItems.first ?? NSMenuItem(
            title: MenuCommand.enterFullScreen.title, action: MainMenuCleaner.fullScreenAction, keyEquivalent: "f")
        if let shortcut: MenuShortcut = MenuCommand.enterFullScreen.shortcut {
            item.keyEquivalent = String(shortcut.key)
            item.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.control]
        }
        item.target = nil // first responder: the key window
        let zoomIndex: Int? = windowsMenu.items.firstIndex { (i: NSMenuItem) -> Bool in i.action == MainMenuCleaner.zoomAction }
        windowsMenu.insertItem(item, at: zoomIndex.map { $0 + 1 } ?? 0)
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
