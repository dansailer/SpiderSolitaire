#if canImport(SwiftUI)
import SpiderCore
import SwiftUI

@main
struct SpiderSolitaireApp: App {
    var body: some Scene {
        WindowGroup("Spider Solitaire") {
            BoardView()
                .frame(minWidth: 800, minHeight: 600)
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
