#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore
import SwiftUI

@main
struct SpiderSolitaireApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate: AppDelegate
    @StateObject private var model: GameModel = GameModel()

    static let boardWindowID: String = "board"

    init() {
        MainMenuCleaner.prepare()
    }

    var body: some Scene {
        // One game window (a `Window`, not a `WindowGroup`): no New Window, no tabs.
        Window("Spider Solitaire", id: SpiderSolitaireApp.boardWindowID) {
            BoardView(model: model)
                .frame(minWidth: 640, minHeight: 480)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            GameCommands(model: model)
            EmptiedStandardMenus()
        }

        Window("Achievements", id: AchievementsView.windowID) {
            AchievementsView(model: model)
        }
        .defaultSize(width: 720, height: 560)

        Window(MenuCommand.help.title, id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(WindowResizability.contentMinSize)

        // Spider Solitaire ▸ Settings… (⌘,)
        Settings {
            SettingsView(model: model)
        }
    }
}

/// The menu bar (SPEC.md §3.5). Titles and shortcuts come from `MenuCommand` in SpiderBoard,
/// where tests check them for clashes. Edit, View and File are emptied here and removed by
/// `MainMenuCleaner`; AppKit then puts Enter Full Screen in the Window menu.
struct GameCommands: Commands {
    @ObservedObject var model: GameModel

    var body: some Commands {
        CommandGroup(replacing: CommandGroupPlacement.appInfo) {
            Button("About Spider Solitaire") { AboutPanel.show() }
        }
        // Help ▸ Spider Solitaire Help (⌘?); macOS adds the search field.
        CommandGroup(replacing: CommandGroupPlacement.help) {
            HelpMenuButton()
        }

        // Groups keep each builder block at 10 items or fewer.
        CommandMenu(MenuCommand.Menu.game.rawValue) {
            Group {
                CommandButton(MenuCommand.newGame) { model.requestNewGame(nil) }
                CommandButton(MenuCommand.restartGame) { model.requestRestart() }
                Divider()
                CommandButton(MenuCommand.undo) { model.undo() }
                    .disabled(!model.canUndo)
                CommandButton(MenuCommand.redo) { model.redo() }
                    .disabled(!model.canRedo)
                Divider()
            }
            Group {
                CommandButton(MenuCommand.dealNextRow) { model.deal() }
                CommandButton(MenuCommand.showHint) { model.showHint() }
                Divider()
                Menu(MenuCommand.Menu.difficulty.rawValue) {
                    DifficultyItem(model: model, command: MenuCommand.oneSuit, difficulty: Difficulty.oneSuit)
                    DifficultyItem(model: model, command: MenuCommand.twoSuits, difficulty: Difficulty.twoSuits)
                    DifficultyItem(model: model, command: MenuCommand.fourSuits, difficulty: Difficulty.fourSuits)
                }
                Divider()
            }
            Group {
                CommandButton(MenuCommand.statistics) { model.showStatisticsSheet = true }
                AchievementsMenuButton()
                Divider()
                CommandButton(MenuCommand.saveGame) { model.saveGame() }
                CommandButton(MenuCommand.openSavedGame) { model.requestOpenSavedGame() }
                    .disabled(!model.hasSavedGame)
                Divider()
                CommandButton(MenuCommand.closeWindow) { NSApplication.shared.keyWindow?.performClose(nil) }
            }
        }
    }
}

/// Empties SwiftUI's File, Edit and View menus (kept in a separate `Commands` because a
/// commands builder takes at most 10 items); `MainMenuCleaner` then removes the empty menus.
struct EmptiedStandardMenus: Commands {
    var body: some Commands {
        // File menu: nothing (single window; saving lives in the Game menu).
        CommandGroup(replacing: CommandGroupPlacement.newItem) {}
        CommandGroup(replacing: CommandGroupPlacement.saveItem) {}
        CommandGroup(replacing: CommandGroupPlacement.importExport) {}
        CommandGroup(replacing: CommandGroupPlacement.printItem) {}
        // Edit menu: nothing (Undo and Redo are in the Game menu).
        CommandGroup(replacing: CommandGroupPlacement.undoRedo) {}
        CommandGroup(replacing: CommandGroupPlacement.pasteboard) {}
        CommandGroup(replacing: CommandGroupPlacement.textEditing) {}
        CommandGroup(replacing: CommandGroupPlacement.textFormatting) {}
        // View menu: nothing.
        CommandGroup(replacing: CommandGroupPlacement.toolbar) {}
        CommandGroup(replacing: CommandGroupPlacement.sidebar) {}
    }
}

/// A menu button whose title and shortcut come from the `MenuCommand` table.
struct CommandButton: View {
    let command: MenuCommand
    let action: () -> Void

    init(_ command: MenuCommand, action: @escaping () -> Void) {
        self.command = command
        self.action = action
    }

    var body: some View {
        Button(command.title, action: action)
            .keyboardShortcut(command.keyboardShortcut)
    }
}

/// Game ▸ Difficulty ▸ One/Two/Four Suits: checked for the current game; choosing one starts a
/// new game at that difficulty (asking first if a game is in progress).
struct DifficultyItem: View {
    @ObservedObject var model: GameModel
    let command: MenuCommand
    let difficulty: Difficulty

    var body: some View {
        Toggle(command.title, isOn: Binding<Bool>(
            get: { model.game.state.difficulty == difficulty },
            set: { (_: Bool) in model.requestNewGame(difficulty) }
        ))
        .keyboardShortcut(command.keyboardShortcut)
    }
}

extension MenuCommand {
    var keyboardShortcut: KeyboardShortcut? {
        guard let s: MenuShortcut = shortcut else { return nil }
        var modifiers: EventModifiers = []
        if s.command { modifiers.insert(EventModifiers.command) }
        if s.shift { modifiers.insert(EventModifiers.shift) }
        if s.option { modifiers.insert(EventModifiers.option) }
        if s.control { modifiers.insert(EventModifiers.control) }
        return KeyboardShortcut(KeyEquivalent(s.key), modifiers: modifiers)
    }
}

/// Quit handling (save / don't save / prompt, per Options), close-window-quits, menu clean-up,
/// and "any key skips the win animation".
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: GameModel?
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuCleaner.shared.start()
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
