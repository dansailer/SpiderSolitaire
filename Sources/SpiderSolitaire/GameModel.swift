#if canImport(SwiftUI)
import Foundation
import SpiderBoard
import SpiderCore
import SwiftUI

/// Glue between SwiftUI and the pure engine. Holds no rules: SpiderGame decides what is legal,
/// PointerController decides what a gesture means, BoardLayout decides where things go,
/// BoardAnimations / HintCycler hold the animation and hint state. This class only sequences
/// those steps in time and wraps them in `withAnimation`.
@MainActor
final class GameModel: ObservableObject {
    static let cannotDealMessage: String = "You are not allowed to deal a new row while there are any empty slots."
    static let undoPolicyKey: String = "undoPolicy"

    @Published private(set) var game: SpiderGame
    @Published private(set) var pointer: PointerController = PointerController()
    @Published private(set) var animations: BoardAnimations = BoardAnimations()
    @Published private(set) var highlight: HintHighlight? = nil
    @Published private(set) var undoPolicy: UndoPolicy
    /// Text for the XP-style info alert (nil = no alert).
    @Published var alertMessage: String? = nil
    @Published var showWinAlert: Bool = false
    /// "There are no more moves." (stuck after an action, or M pressed with nothing to suggest).
    @Published var showNoMovesAlert: Bool = false

    private var hintCycler: HintCycler = HintCycler()
    /// Bumped to cancel scheduled animation steps (any new action settles running animations).
    private var animationGeneration: Int = 0
    /// Bumped to cancel a running hint flash.
    private var highlightGeneration: Int = 0

    /// One timed step of an animation or hint flash.
    private enum Step: Sendable {
        case releaseDealt(Int)
        case land(Int)
        case finishSlot(Int)
        case afterAnimations
        case highlight(HintHighlight?)
    }

    init(difficulty: Difficulty = Difficulty.oneSuit) {
        let stored: String = UserDefaults.standard.string(forKey: GameModel.undoPolicyKey) ?? ""
        let policy: UndoPolicy = UndoPolicy(rawValue: stored) ?? UndoPolicy.unlimited
        undoPolicy = policy
        game = SpiderGame(difficulty: difficulty, seed: GameModel.randomSeed(), undoPolicy: policy)
    }

    static func randomSeed() -> UInt64 { UInt64.random(in: UInt64.min...UInt64.max) }

    // MARK: Commands

    func newGame(_ difficulty: Difficulty) {
        settleAnimations(announce: false)
        clearHighlight()
        pointer.reset()
        hintCycler.reset()
        game = SpiderGame(difficulty: difficulty, seed: GameModel.randomSeed(), undoPolicy: undoPolicy)
        showWinAlert = false
        showNoMovesAlert = false
    }

    func deal() {
        perform(Action.deal)
    }

    func undo() {
        guard game.canUndo else { return }
        settleAnimations(announce: false)
        clearHighlight()
        pointer.reset()
        showNoMovesAlert = false
        withAnimation(Animation.easeInOut(duration: 0.2)) {
            _ = try? game.undo()
        }
    }

    func setUndoPolicy(_ policy: UndoPolicy) {
        undoPolicy = policy
        game.undoPolicy = policy
        UserDefaults.standard.set(policy.rawValue, forKey: GameModel.undoPolicyKey)
    }

    /// M key / click on the score box: flash the next hint (source run, then target).
    func showHint() {
        settleAnimations(announce: true)
        guard !game.state.isWon else { return }
        let step: HintStep = hintCycler.next(for: game.state)
        let sequence: [HintHighlight] = HintHighlight.sequence(for: step)
        guard !sequence.isEmpty else {
            clearHighlight()
            showNoMovesAlert = true
            return
        }
        highlightGeneration += 1
        highlight = sequence[0]
        for i in 1..<(sequence.count + 1) {
            let next: HintHighlight? = i < sequence.count ? sequence[i] : nil
            schedule(Step.highlight(next), after: HintHighlight.beat * Double(i))
        }
    }

    // MARK: Pointer (one DragGesture with minimumDistance 0 drives everything)

    func pointerChanged(start: CGPoint, translation: CGSize, layout: BoardLayout) {
        if !animations.isIdle { settleAnimations(announce: true) }
        if highlight != nil { clearHighlight() }
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
        case .hint:
            pointer = next
            showHint()
        case .perform(let action):
            // `perform` clears the drag inside the same animation as the state change.
            perform(action)
        }
    }

    // MARK: Actions and their animations

    private func perform(_ action: Action) {
        settleAnimations(announce: true)
        clearHighlight()
        if action == Action.deal, !game.state.canDeal {
            pointer.reset()
            if !game.state.stock.isEmpty, !game.state.isWon { alertMessage = GameModel.cannotDealMessage }
            return
        }

        let dealsBefore: Int = game.state.dealsRemaining
        var outcome: ActionOutcome? = nil
        var flightsStart: Double = 0

        if action == Action.deal {
            // No implicit animation: the dealt cards stay drawn on the pile they came from and
            // leave one by one below.
            pointer.reset()
            outcome = try? game.perform(action)
            if let outcome {
                animations.beginDeal(outcome, dealsBefore: dealsBefore)
                animations.beginFlights(outcome.completedRuns, columns: game.state.columns)
                for (i, id) in outcome.dealtCardIDs.enumerated() {
                    schedule(Step.releaseDealt(id), after: BoardAnimations.dealStagger * Double(i))
                }
                flightsStart = BoardAnimations.dealStagger * Double(outcome.dealtCardIDs.count)
                    + BoardAnimations.dealDuration
            }
        } else {
            withAnimation(Animation.easeOut(duration: 0.22)) {
                pointer.reset()
                outcome = try? game.perform(action)
                if let outcome {
                    animations.beginFlights(outcome.completedRuns, columns: game.state.columns)
                }
            }
            flightsStart = 0.25
        }

        guard let outcome else { return }
        var t: Double = flightsStart
        for run in outcome.completedRuns {
            let order: [Int] = animations.takeOffOrder(slot: run.foundationSlot)
            for (j, id) in order.enumerated() {
                schedule(Step.land(id), after: t + BoardAnimations.flyStagger * Double(j))
            }
            t += BoardAnimations.flyStagger * Double(order.count) + BoardAnimations.flyDuration
            schedule(Step.finishSlot(run.foundationSlot), after: t)
        }
        schedule(Step.afterAnimations, after: outcome.completedRuns.isEmpty && action != Action.deal ? 0.25 : t)
    }

    private func apply(_ step: Step) {
        switch step {
        case .releaseDealt(let id):
            withAnimation(Animation.easeOut(duration: BoardAnimations.dealDuration)) {
                _ = animations.releaseDealtCard(id)
            }
        case .land(let id):
            withAnimation(Animation.easeIn(duration: BoardAnimations.flyDuration)) {
                animations.land(id)
            }
        case .finishSlot(let slot):
            animations.finishSlot(slot)
        case .afterAnimations:
            announceEndState()
        case .highlight(let next):
            highlight = next
        }
    }

    /// Win dialog or "no more moves" once the board has come to rest.
    private func announceEndState() {
        if game.state.isWon {
            showWinAlert = true
        } else if game.state.isStuck {
            showNoMovesAlert = true
        }
    }

    /// Jump every running animation to its end state (used when the player acts mid-animation).
    private func settleAnimations(announce: Bool) {
        let wasRunning: Bool = !animations.isIdle
        animationGeneration += 1
        if wasRunning {
            animations = BoardAnimations()
            if announce { announceEndState() }
        }
    }

    private func clearHighlight() {
        highlightGeneration += 1
        highlight = nil
    }

    private func schedule(_ step: Step, after seconds: Double) {
        let isHighlight: Bool
        if case .highlight = step { isHighlight = true } else { isHighlight = false }
        let generation: Int = isHighlight ? highlightGeneration : animationGeneration
        let nanoseconds: UInt64 = UInt64(max(0, seconds) * 1_000_000_000)
        // Created on the main actor, so the task body runs on the main actor too.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            let current: Int = isHighlight ? self.highlightGeneration : self.animationGeneration
            guard current == generation else { return }
            self.apply(step)
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
