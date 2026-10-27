#if canImport(SwiftUI)
import SpiderCore
import SwiftUI

@main
struct SpiderSolitaireApp: App {
    @StateObject private var model: GameModel = GameModel()

    var body: some Scene {
        WindowGroup("Spider Solitaire") {
            BoardView(model: model)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            GameCommands(model: model)
        }
    }
}

/// Game menu so far: new game, undo, deal, hint, undo mode. The full XP menu (difficulty sheet,
/// statistics, save/open) is M6.
struct GameCommands: Commands {
    @ObservedObject var model: GameModel

    private var classicUndo: Binding<Bool> {
        Binding<Bool>(
            get: { model.undoPolicy == UndoPolicy.xpClassic },
            set: { (on: Bool) in model.setUndoPolicy(on ? UndoPolicy.xpClassic : UndoPolicy.unlimited) }
        )
    }

    var body: some Commands {
        CommandGroup(replacing: CommandGroupPlacement.newItem) {
            Button("New Game") { model.newGame(model.game.state.difficulty) }
                .keyboardShortcut("n", modifiers: EventModifiers.command)
            Menu("New Game With Difficulty") {
                ForEach(Difficulty.allCases, id: \.self) { (difficulty: Difficulty) in
                    Button(difficulty.displayName) { model.newGame(difficulty) }
                }
            }
        }
        CommandGroup(replacing: CommandGroupPlacement.undoRedo) {
            Button("Undo") { model.undo() }
                .keyboardShortcut("z", modifiers: EventModifiers.command)
                .disabled(!model.game.canUndo)
        }
        CommandMenu("Game") {
            Button("Deal Next Row") { model.deal() }
                .keyboardShortcut("d", modifiers: [])
            Button("Show an Available Move") { model.showHint() }
                .keyboardShortcut("m", modifiers: [])
            Divider()
            Toggle("Classic XP Undo (Stops at Deals and Completed Suits)", isOn: classicUndo)
        }
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
