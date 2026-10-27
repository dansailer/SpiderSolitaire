#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore
import SpiderPersistence
import SwiftUI

/// AppKit app lifecycle with SwiftUI views inside the windows. There is no SwiftUI `App` or
/// `Commands`: SwiftUI rebuilt the menu bar whenever the observed game changed and re-added its
/// View and Format menus each time (they flickered in and out). The app builds the bar itself,
/// once (`MainMenuBuilder`).
@main
enum SpiderSolitaireMain {
    @MainActor
    static func main() {
        // Before NSApplication exists: AppKit reads these defaults when it starts up.
        MainMenuBuilder.prepare()
        let app: NSApplication = NSApplication.shared
        let delegate: AppDelegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(NSApplication.ActivationPolicy.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// The four windows. Each is created on first use and kept (closing hides it), so its size and
/// position survive; the board's frame is also saved between launches.
@MainActor
final class WindowController: NSObject, NSWindowDelegate {
    private let model: GameModel
    private let updates: UpdateController
    private var board: NSWindow?
    private var achievements: NSWindow?
    private var help: NSWindow?
    private var settings: NSWindow?

    init(model: GameModel, updates: UpdateController) {
        self.model = model
        self.updates = updates
    }

    @discardableResult
    func showBoard() -> NSWindow {
        let window: NSWindow = board ?? makeWindow(
            title: "Spider Solitaire", autosave: "SpiderSolitaireBoard",
            size: NSSize(width: 800, height: 600), resizable: true,
            content: BoardView(model: model).frame(minWidth: 640, minHeight: 480))
        window.collectionBehavior.insert(NSWindow.CollectionBehavior.fullScreenPrimary)
        board = window
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @discardableResult
    func showAchievements() -> NSWindow {
        let window: NSWindow = achievements ?? makeWindow(
            title: "Achievements", autosave: "SpiderSolitaireAchievements",
            size: NSSize(width: 720, height: 560), resizable: true,
            content: AchievementsView(model: model))
        achievements = window
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @discardableResult
    func showHelp() -> NSWindow {
        let window: NSWindow = help ?? makeWindow(
            title: MenuCommand.help.title, autosave: "SpiderSolitaireHelp",
            size: NSSize(width: 560, height: 640), resizable: true,
            content: HelpView())
        help = window
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @discardableResult
    func showSettings() -> NSWindow {
        let window: NSWindow = settings ?? {
            let tabs: SettingsTabViewController = SettingsTabViewController(model: model, updates: updates)
            let w: NSWindow = NSWindow(contentViewController: tabs)
            w.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
            w.toolbarStyle = NSWindow.ToolbarStyle.preference
            w.tabbingMode = NSWindow.TabbingMode.disallowed
            w.isReleasedWhenClosed = false
            w.collectionBehavior.insert(NSWindow.CollectionBehavior.fullScreenNone)
            if let first: NSView = tabs.tabViewItems.first?.viewController?.view {
                w.setContentSize(first.fittingSize)
            }
            w.center()
            w.setFrameAutosaveName("SpiderSolitaireSettingsWindow")
            return w
        }()
        settings = window
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func makeWindow<Content: View>(title: String, autosave: String, size: NSSize?, resizable: Bool,
                                           content: Content) -> NSWindow {
        let controller: NSHostingController<Content> = NSHostingController<Content>(rootView: content)
        controller.sizingOptions = resizable ? [NSHostingSizingOptions.minSize] : [NSHostingSizingOptions.preferredContentSize]
        var style: NSWindow.StyleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable,
                                         NSWindow.StyleMask.miniaturizable]
        if resizable { style.insert(NSWindow.StyleMask.resizable) }
        let window: NSWindow = NSWindow(contentRect: NSRect(origin: NSPoint.zero, size: size ?? NSSize(width: 480, height: 400)),
                                        styleMask: style, backing: NSWindow.BackingStoreType.buffered, defer: false)
        window.contentViewController = controller
        window.title = title
        window.tabbingMode = NSWindow.TabbingMode.disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let size { window.setContentSize(size) }
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }

    /// Closing the game window quits the app (the usual quit-time save rules apply).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === board else { return true }
        NSApplication.shared.terminate(nil)
        return false
    }
}

/// `--snapshot <dir>` (website screenshots, SPEC.md §9): a throwaway store, a two-suit game part
/// way through, then each window's content rendered to PNG in `dir`, and quit. Uses only
/// `cacheDisplay`, so it needs no screen recording permission.
@MainActor
enum SnapshotMode {
    static var outputDirectory: URL? {
        let args: [String] = CommandLine.arguments
        guard let i: Int = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func makeModel() -> GameModel {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiderSolitaireSnapshot-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let store: SpiderStore = SpiderStore(directory: directory)
        var options: Options = Options()
        options.difficulty = Difficulty.twoSuits
        options.openOnStart = StartOpenPolicy.never
        options.checkForUpdatesAutomatically = false
        try? store.saveOptions(options)
        return GameModel(store: store)
    }

    static func run(model: GameModel, windows: WindowController, into directory: URL) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            model.prepareSnapshot(difficulty: Difficulty.twoSuits, moves: 38)
            let board: NSWindow = windows.showBoard()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            save(board, "board", directory)
            let help: NSWindow = windows.showHelp()
            try? await Task.sleep(nanoseconds: 800_000_000)
            save(help, "help", directory)
            let achievements: NSWindow = windows.showAchievements()
            try? await Task.sleep(nanoseconds: 800_000_000)
            save(achievements, "achievements", directory)
            let settings: NSWindow = windows.showSettings()
            for (index, tab) in SettingsTab.allCases.enumerated() {
                (settings.contentViewController as? SettingsTabViewController)?.selectedTabViewItemIndex = index
                try? await Task.sleep(nanoseconds: 900_000_000)
                save(settings, "settings-" + tab.rawValue, directory)
            }
            exit(0)
        }
    }

    private static func save(_ window: NSWindow?, _ name: String, _ directory: URL) {
        guard let view: NSView = window?.contentView,
              let rep: NSBitmapImageRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data: Data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        let url: URL = directory.appendingPathComponent(name + ".png")
        try? data.write(to: url)
        print("SNAPSHOT " + url.path)
    }
}

/// `--menu-probe <seconds>` (debug check, SPEC.md §3.5): plays moves for that long and prints
/// the menu bar four times a second, then the set of distinct menu bars seen, and quits with
/// status 0 only if the bar never changed, matches `MenuBarLayout`, and shows Full Screen once.
@MainActor
enum MenuProbe {
    /// Returns whether the probe runs.
    @discardableResult
    static func startIfRequested(menuController: MenuController) -> Bool {
        let args: [String] = CommandLine.arguments
        guard let i: Int = args.firstIndex(of: "--menu-probe") else { return false }
        let seconds: Double = (i + 1 < args.count ? Double(args[i + 1]) : nil) ?? 10
        Task { @MainActor in
            var seen: [String: Int] = [:]
            let steps: [MenuCommand] = [.showHint, .dealNextRow, .undo, .redo, .showHint, .undo]
            let ticks: Int = Int(seconds * 4)
            for tick in 0..<ticks {
                if tick % 2 == 0 { menuController.perform(steps[(tick / 2) % steps.count]) }
                let snapshot: String = MainMenuBuilder.snapshot()
                seen[snapshot, default: 0] += 1
                print(String(format: "MENUPROBE %6.2fs %@", Double(tick) / 4, snapshot))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let app: NSApplication = NSApplication.shared
            let tops: [String] = app.mainMenu?.items.map { (item: NSMenuItem) -> String in item.title } ?? []
            let expected: [String] = MenuBarLayout.menuBar.map { (top: MenuBarLayout.TopMenu) -> String in top.title }
            let fullScreen: Int = app.windowsMenu?.items.filter { (item: NSMenuItem) -> Bool in
                !item.isHidden && item.action == #selector(NSWindow.toggleFullScreen(_:))
            }.count ?? 0
            print("MENUPROBE distinct menu bars: \(seen.count)")
            for (bar, count) in seen { print("MENUPROBE \(count)x \(bar)") }
            print("MENUPROBE top menus as designed: \(tops == expected); visible Full Screen items: \(fullScreen)")
            fflush(stdout)
            exit(seen.count == 1 && tops == expected && fullScreen == 1 ? 0 : 1)
        }
        return true
    }
}

/// Owns the model, the windows and the menu bar. Quit handling (save / don't save / prompt, per
/// Options), close-window-quits, and "any key skips the win animation".
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: GameModel?
    private var windows: WindowController?
    private var menuController: MenuController?
    private var updates: UpdateController?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let snapshotDirectory: URL? = SnapshotMode.outputDirectory
        let model: GameModel = snapshotDirectory != nil ? SnapshotMode.makeModel() : GameModel()
        let updates: UpdateController = UpdateController()
        let windows: WindowController = WindowController(model: model, updates: updates)
        let menuController: MenuController = MenuController(model: model, windows: windows, updates: updates)
        self.model = model
        self.updates = updates
        self.windows = windows
        self.menuController = menuController
        MainMenuBuilder.install(target: menuController)
        windows.showBoard()
        NSApplication.shared.activate()
        if let snapshotDirectory {
            SnapshotMode.run(model: model, windows: windows, into: snapshotDirectory)
        } else if !MenuProbe.startIfRequested(menuController: menuController) {
            updates.checkAutomaticallyIfDue(enabled: model.options.checkForUpdatesAutomatically)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) {
            [weak self] (event: NSEvent) -> NSEvent? in
            guard let model = self?.model, model.isCelebrating else { return event }
            model.skipCelebration()
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Clicking the Dock icon with no window open brings the game back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windows?.showBoard() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return NSApplication.TerminateReply.terminateNow }
        switch model.quitDecision {
        case .nothing:
            model.persistAll()
        case .save:
            model.saveForQuit()
        case .discardAsLoss:
            model.discardForQuit()
        case .ask:
            let alert: NSAlert = NSAlert()
            alert.messageText = "Do you want to save this game?"
            alert.informativeText = "If you don't save it, it counts as a loss."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let response: NSApplication.ModalResponse = alert.runModal()
            if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                model.saveForQuit()
            } else if response == NSApplication.ModalResponse.alertSecondButtonReturn {
                model.discardForQuit()
            } else {
                return NSApplication.TerminateReply.terminateCancel
            }
        }
        return NSApplication.TerminateReply.terminateNow
    }
}
#else
// SwiftUI is unavailable (e.g. Linux CI): keep the target buildable so `swift build` works everywhere.
import SpiderCore

@main
enum SpiderSolitaireStub {
    static func main() {
        let game = SpiderGame(difficulty: .oneSuit, seed: 1)
        print("SpiderSolitaire UI needs macOS. Core OK: score \(game.state.score), \(game.state.dealsRemaining) deals left.")
    }
}
#endif
