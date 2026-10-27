#if canImport(SwiftUI)
import AppKit
import SpiderBoard

/// Final touches SwiftUI's `Commands` can't express (SPEC.md §3.5): the menu bar is exactly the
/// app menu, Game, Window and Help. SwiftUI still inserts File, Edit and View menus (emptied by
/// `EmptiedStandardMenus`), so this removes them. What to remove is decided by `MenuBarPlan`
/// (SpiderBoard, unit-tested) from the menus' structure and key equivalents, never their titles.
///
/// Enter Full Screen is left to AppKit: once there is no View menu, AppKit puts its own
/// `toggleFullScreen:` item (⌃⌘F, titled Enter / Exit Full Screen) in the Window menu.
///
/// When it runs: at launch, and after SwiftUI rebuilds the menu bar (an item added to the main
/// menu itself), debounced, and never while a menu is open. It changes nothing when the bar is
/// already clean. (An earlier version also reacted to every item added to any menu, including
/// the Window menu filling in its window list as it opened, and then added or removed Full Screen
/// items while the menu was on screen: that was the "long menu, then a short one" flicker.)
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

    private var observers: [NSObjectProtocol] = []
    /// Menus currently open (tracking); cleanup waits until this is zero.
    private var trackingDepth: Int = 0
    private var pending: Bool = false
    private var scheduled: Bool = false

    func start() {
        requestClean()
        let center: NotificationCenter = NotificationCenter.default
        let main: OperationQueue = OperationQueue.main
        observers.append(center.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: main) {
            [weak self] (note: Notification) in
            // Only top-level changes: SwiftUI rebuilding the bar. Items added inside a menu (the
            // Window menu's window list, AppKit's own items) are none of our business.
            let menu: NSMenu? = note.object as? NSMenu
            MainActor.assumeIsolated {
                guard let menu, menu === NSApplication.shared.mainMenu else { return }
                self?.requestClean()
            }
        })
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: main) {
            [weak self] (_: Notification) in
            MainActor.assumeIsolated { if let self { self.trackingDepth += 1 } }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: main) {
            [weak self] (_: Notification) in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.trackingDepth = max(0, self.trackingDepth - 1)
                if self.trackingDepth == 0, self.pending { self.requestClean() }
            }
        })
    }

    /// Debounced: many additions in one SwiftUI pass lead to one cleanup a moment later.
    private func requestClean() {
        pending = true
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            self.scheduled = false
            guard self.trackingDepth == 0 else { return } // runs when tracking ends
            self.pending = false
            self.clean()
        }
    }

    private static func shortcuts(of menu: NSMenu?) -> [MenuShortcut] {
        guard let menu else { return [] }
        return menu.items.flatMap { (item: NSMenuItem) -> [MenuShortcut] in
            var out: [MenuShortcut] = shortcuts(of: item.submenu)
            if let key: Character = item.keyEquivalent.first {
                let flags: NSEvent.ModifierFlags = item.keyEquivalentModifierMask
                out.append(MenuShortcut(key, command: flags.contains(NSEvent.ModifierFlags.command),
                                        shift: flags.contains(NSEvent.ModifierFlags.shift),
                                        option: flags.contains(NSEvent.ModifierFlags.option),
                                        control: flags.contains(NSEvent.ModifierFlags.control)))
            }
            return out
        }
    }

    func clean() {
        let app: NSApplication = NSApplication.shared
        guard trackingDepth == 0, let mainMenu: NSMenu = app.mainMenu else { return }
        let topItems: [NSMenuItem] = Array(mainMenu.items.dropFirst()) // index 0 is the app menu
        let tops: [MenuBarPlan.TopMenu] = topItems.map { (item: NSMenuItem) -> MenuBarPlan.TopMenu in
            MenuBarPlan.TopMenu(isWindowsMenu: item.submenu != nil && item.submenu === app.windowsMenu,
                                isHelpMenu: item.submenu != nil && item.submenu === app.helpMenu,
                                shortcuts: MainMenuCleaner.shortcuts(of: item.submenu))
        }
        if let i: Int = MenuBarPlan.helpMenuToAdopt(tops), let menu: NSMenu = topItems[i].submenu {
            app.helpMenu = menu
        }
        for i in MenuBarPlan.menusToRemove(tops) {
            mainMenu.removeItem(topItems[i])
        }
        if let windowsMenu: NSMenu = app.windowsMenu {
            let actions: [String?] = windowsMenu.items.map { (item: NSMenuItem) -> String? in
                item.action.map { (selector: Selector) -> String in NSStringFromSelector(selector) }
            }
            for i in MenuBarPlan.windowItemsToRemove(actions: actions) {
                windowsMenu.removeItem(at: i)
            }
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
