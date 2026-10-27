#if canImport(SwiftUI)
import AppKit
import SpiderCore
import SwiftUI

@main
struct SpiderSolitaireApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate: AppDelegate
    @StateObject private var model: GameModel = GameModel()

    var body: some Scene {
        WindowGroup("Spider Solitaire") {
            BoardView(model: model)
                .frame(minWidth: 640, minHeight: 480)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            GameCommands(model: model)
        }
    }
}

/// XP's Game menu (Mac shortcuts per SPEC.md §3.5). F2 is handled by AppDelegate's key monitor.
struct GameCommands: Commands {
    @ObservedObject var model: GameModel

    var body: some Commands {
        // One window, no documents: drop File ▸ New Window, and keep Undo in the Game menu like XP.
        CommandGroup(replacing: CommandGroupPlacement.newItem) {}
        CommandGroup(replacing: CommandGroupPlacement.undoRedo) {}
        CommandGroup(replacing: CommandGroupPlacement.appSettings) {
            Button("Options…") { model.showOptionsSheet = true }
                .keyboardShortcut(",", modifiers: EventModifiers.command)
        }

        CommandMenu("Game") {
            Button("New Game") { model.requestNewGame(nil) }
                .keyboardShortcut("n", modifiers: EventModifiers.command)
            Button("Restart This Game") { model.requestRestart() }
                .keyboardShortcut("n", modifiers: [EventModifiers.command, EventModifiers.shift])
            Divider()
            Button("Undo") { model.undo() }
                .keyboardShortcut("z", modifiers: EventModifiers.command)
                .disabled(!model.canUndo)
            Button("Deal Next Row") { model.deal() }
                .keyboardShortcut("d", modifiers: [])
            Button("Show an Available Move") { model.showHint() }
                .keyboardShortcut("m", modifiers: [])
            Divider()
            Button("Difficulty…") { model.showDifficultySheet = true }
                .keyboardShortcut("d", modifiers: EventModifiers.command)
            Button("Statistics…") { model.showStatisticsSheet = true }
                .keyboardShortcut("i", modifiers: EventModifiers.command)
            Button("Options…") { model.showOptionsSheet = true }
            Divider()
            Button("Save This Game") { model.saveGame() }
                .keyboardShortcut("s", modifiers: EventModifiers.command)
            Button("Open Last Saved Game") { model.requestOpenSavedGame() }
                .keyboardShortcut("o", modifiers: EventModifiers.command)
                .disabled(!model.hasSavedGame)
            Divider()
            Button("Exit") { NSApplication.shared.terminate(nil) }
        }
    }
}

/// Quit handling (save / don't save / prompt, per Options), close-window-quits, and the F2 key.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: GameModel?
    private var keyMonitor: Any?

    /// Virtual key code of F2 on Mac keyboards.
    static let f2KeyCode: UInt16 = 120

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) {
            [weak self] (event: NSEvent) -> NSEvent? in
            guard event.keyCode == AppDelegate.f2KeyCode, let model = self?.model else { return event }
            model.requestNewGame(nil)
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
