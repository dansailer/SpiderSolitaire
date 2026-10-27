#if canImport(SwiftUI)
import Foundation
import SpiderBoard
import SpiderCore
import SwiftUI

/// Glue between SwiftUI and the pure engine. Holds no rules: SpiderGame decides what is legal,
/// PointerController decides what a gesture means, BoardLayout decides where things go.
@MainActor
final class GameModel: ObservableObject {
    static let cannotDealMessage = "You are not allowed to deal a new row while there are any empty slots."

    @Published private(set) var game: SpiderGame
    @Published private(set) var pointer: PointerController = PointerController()
    /// Text for the XP-style info alert (nil = no alert).
    @Published var alertMessage: String?
    @Published var showWinAlert: Bool = false

    init(difficulty: Difficulty = .oneSuit) {
        game = SpiderGame(difficulty: difficulty, seed: GameModel.randomSeed())
    }

    static func randomSeed() -> UInt64 { UInt64.random(in: UInt64.min...UInt64.max) }

    // MARK: Commands

    func newGame(_ difficulty: Difficulty) {
        pointer.reset()
        game = SpiderGame(difficulty: difficulty, seed: GameModel.randomSeed())
        showWinAlert = false
    }

    func deal() {
        perform(Action.deal)
    }

    func undo() {
        guard game.canUndo else { return }
        pointer.reset()
        withAnimation(Animation.easeInOut(duration: 0.2)) {
            _ = try? game.undo()
        }
    }

    // MARK: Pointer (one DragGesture with minimumDistance 0 drives everything)

    func pointerChanged(start: CGPoint, translation: CGSize, layout: BoardLayout) {
        var next: PointerController = pointer
        next.pointerChanged(start: BoardPoint(start), translation: BoardSize(translation), state: game.state, layout: layout)
        pointer = next
    }

    func pointerEnded(start: CGPoint, translation: CGSize, layout: BoardLayout) {
        var next: PointerController = pointer
        let result: PointerController.Result = next.pointerEnded(
            start: BoardPoint(start), translation: BoardSize(translation),
            time: ProcessInfo.processInfo.systemUptime, state: game.state, layout: layout)

        switch result {
        case .none:
            pointer = next
        case .snapBack:
            // Clearing the drag inside the animation glides the run back to its column.
            withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.8)) {
                pointer = next
            }
        case .perform(let action):
            // `perform` clears the drag inside the same animation as the state change.
            perform(action)
        }
    }

    // MARK: Private

    private func perform(_ action: Action) {
        if action == Action.deal, !game.state.canDeal {
            pointer.reset()
            if !game.state.stock.isEmpty, !game.state.isWon { alertMessage = GameModel.cannotDealMessage }
            return
        }
        // The pointer reset and the state change share one animation, so a dropped run glides
        // from where the mouse let go to its new column, and dealt cards fly out of the stock.
        withAnimation(Animation.easeOut(duration: 0.22)) {
            pointer.reset()
            if let outcome = try? game.perform(action), outcome.didWin {
                showWinAlert = true
            }
        }
    }
}

extension BoardPoint {
    init(_ p: CGPoint) { self.init(x: Double(p.x), y: Double(p.y)) }
}

extension BoardSize {
    init(_ s: CGSize) { self.init(width: Double(s.width), height: Double(s.height)) }
    var cgSize: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
}

extension BoardRect {
    var cgRect: CGRect { CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height)) }
    var cgCenter: CGPoint { CGPoint(x: CGFloat(midX), y: CGFloat(midY)) }
    var cgSize: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
}
#endif
