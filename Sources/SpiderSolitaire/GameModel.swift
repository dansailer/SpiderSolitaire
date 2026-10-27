#if canImport(SwiftUI)
import Foundation
import SpiderBoard
import SpiderCore
import SpiderPersistence
import SwiftUI

/// The one dialog the board can show at a time (a single `.alert` drives all of them).
enum BoardAlert: Identifiable, Sendable {
    case info(String)
    case noMoves
    case won(score: Int)
    case confirmAbandon(AbandonReason)
    case openSavedGame

    var id: String {
        switch self {
        case .info(let text): return "info:" + text
        case .noMoves: return "noMoves"
        case .won: return "won"
        case .confirmAbandon: return "abandon"
        case .openSavedGame: return "openSaved"
        }
    }

    var title: String {
        switch self {
        case .won: return "Congratulations, you won!"
        default: return "Spider Solitaire"
        }
    }

    var message: String {
        switch self {
        case .info(let text): return text
        case .noMoves: return "There are no more moves."
        case .won(let score): return "Score: \(score). Do you want to start another game?"
        case .confirmAbandon: return "This game is in progress and will count as a loss. Do you want to quit this game?"
        case .openSavedGame: return "Do you want to open your previously saved game?"
        }
    }
}

/// Glue between SwiftUI and the pure modules. Holds no rules: SessionController owns the game
/// lifecycle and statistics, SpiderGame the rules, PointerController the gestures, BoardLayout
/// the geometry, BoardAnimations / HintCycler the animation and hint state, SpiderStore the files.
/// This class sequences those in time and wraps them in `withAnimation`.
@MainActor
final class GameModel: ObservableObject {
    static let cannotDealMessage: String = "You are not allowed to deal a new row while there are any empty slots."

    @Published private(set) var session: SessionController
    @Published private(set) var pointer: PointerController = PointerController()
    @Published private(set) var animations: BoardAnimations = BoardAnimations()
    @Published private(set) var highlight: HintHighlight? = nil
    @Published private(set) var hasSavedGame: Bool = false
    @Published var alert: BoardAlert? = nil
    @Published var showDifficultySheet: Bool = false
    @Published var showStatisticsSheet: Bool = false
    @Published var showOptionsSheet: Bool = false

    private let store: SpiderStore
    private var hintCycler: HintCycler = HintCycler()
    /// Bumped to cancel scheduled animation steps (any new action settles running animations).
    private var animationGeneration: Int = 0
    /// Bumped to cancel a running hint flash.
    private var highlightGeneration: Int = 0

    /// One timed step of an animation, hint flash or deferred request.
    private enum Step: Sendable {
        case releaseDealt(Int)
        case land(Int)
        case finishSlot(Int)
        case afterAnimations
        case highlight(HintHighlight?)
        case newGame(Difficulty)
        /// Alert buttons that lead to another alert run after the first one has gone away.
        case request(AbandonReason)
        case present(BoardAlert)
    }

    init(store: SpiderStore = SpiderStore.standard()) {
        self.store = store
        let options: Options = store.loadOptions()
        session = SessionController(options: options, statistics: store.loadStatistics(), seed: GameModel.randomSeed())

        switch SessionController.launchDecision(options: options, hasSavedGame: store.hasSavedGame) {
        case .newGame:
            break
        case .resumeSaved:
            if let saved: SavedSession = store.takeSavedGame() { session.open(saved) }
        case .discardSaved:
            if let saved: SavedSession = store.takeSavedGame() { session.discard(saved) }
        case .ask:
            alert = BoardAlert.openSavedGame
        }
        hasSavedGame = store.hasSavedGame
        persistStatistics()
    }

    static func randomSeed() -> UInt64 { UInt64.random(in: UInt64.min...UInt64.max) }

    var game: SpiderGame { session.game }
    var options: Options { session.options }
    var statistics: Statistics { session.statistics }
    var canUndo: Bool { session.canUndo }

    // MARK: Game menu

    /// New Game (⌘N / F2), Difficulty dialog OK. `nil` keeps the current difficulty.
    func requestNewGame(_ difficulty: Difficulty?) {
        requestAbandon(AbandonReason.newGame(difficulty ?? game.state.difficulty))
    }

    func requestRestart() {
        requestAbandon(AbandonReason.restart)
    }

    func requestOpenSavedGame() {
        guard store.hasSavedGame else {
            hasSavedGame = false
            alert = BoardAlert.info("There is no saved game.")
            return
        }
        requestAbandon(AbandonReason.openSavedGame)
    }

    func saveGame() {
        do {
            try store.saveGame(session.session)
            hasSavedGame = true
            alert = BoardAlert.info("Your game has been saved.")
        } catch {
            alert = BoardAlert.info("The game could not be saved: \(error.localizedDescription)")
        }
    }

    /// Difficulty dialog OK: close the sheet first, then start (and maybe confirm) once it is gone.
    func chooseDifficulty(_ difficulty: Difficulty) {
        showDifficultySheet = false
        schedule(Step.newGame(difficulty), after: 0.3, cancellable: false)
    }

    func applyOptions(_ options: Options) {
        session.options = options
        showOptionsSheet = false
        persistOptions()
    }

    func resetStatistics(_ difficulty: Difficulty) {
        session.resetStatistics(difficulty)
        persistStatistics()
    }

    /// New Game button inside an alert: runs once that alert is dismissed, so a follow-up
    /// "quit this game?" confirmation can be shown.
    func requestNewGameFromAlert() {
        alert = nil
        schedule(Step.request(AbandonReason.newGame(game.state.difficulty)), after: 0.3, cancellable: false)
    }

    /// Answers to the dialogs in `BoardAlert`.
    func confirmAbandon(_ reason: AbandonReason) {
        alert = nil
        abandon(reason)
    }

    func answerOpenSavedGame(_ open: Bool) {
        alert = nil
        if let saved: SavedSession = store.takeSavedGame() {
            if open {
                resetTransientState()
                session.open(saved)
            } else {
                session.discard(saved)
            }
        }
        hasSavedGame = store.hasSavedGame
        persistStatistics()
    }

    func deal() {
        perform(Action.deal)
    }

    func undo() {
        guard session.canUndo else { return }
        settleAnimations(announce: false)
        clearHighlight()
        pointer.reset()
        animate(Animation.easeInOut(duration: 0.2)) {
            _ = try? session.undo()
        }
    }

    // MARK: Quit (called by AppDelegate.applicationShouldTerminate)

    var quitDecision: QuitDecision { session.quitDecision }

    func saveForQuit() {
        try? store.saveGame(session.session)
        persistAll()
    }

    func discardForQuit() {
        session.quitWithoutSaving()
        persistAll()
    }

    func persistAll() {
        persistStatistics()
        persistOptions()
    }

    // MARK: Hints

    /// M key / click on the score box: flash the next hint (source run, then target).
    func showHint() {
        settleAnimations(announce: true)
        guard !game.state.isWon else { return }
        let step: HintStep = hintCycler.next(for: game.state)
        let sequence: [HintHighlight] = HintHighlight.sequence(for: step)
        guard !sequence.isEmpty else {
            clearHighlight()
            alert = BoardAlert.noMoves
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
            animate(Animation.spring(response: 0.3, dampingFraction: 0.8)) {
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

    // MARK: Lifecycle internals

    private func requestAbandon(_ reason: AbandonReason) {
        if session.needsAbandonConfirmation {
            alert = BoardAlert.confirmAbandon(reason)
        } else {
            abandon(reason)
        }
    }

    private func abandon(_ reason: AbandonReason) {
        resetTransientState()
        switch reason {
        case .newGame(let difficulty):
            session.startNewGame(difficulty: difficulty, seed: GameModel.randomSeed())
            persistOptions()
        case .restart:
            session.restart()
        case .openSavedGame:
            if let saved: SavedSession = store.takeSavedGame() {
                session.open(saved)
            } else {
                schedule(Step.present(BoardAlert.info("The saved game could not be opened.")), after: 0.3, cancellable: false)
            }
            hasSavedGame = store.hasSavedGame
        }
        persistStatistics()
    }

    private func resetTransientState() {
        settleAnimations(announce: false)
        clearHighlight()
        pointer.reset()
        hintCycler.reset()
        alert = nil
    }

    private func persistStatistics() {
        try? store.saveStatistics(session.statistics)
    }

    private func persistOptions() {
        try? store.saveOptions(session.options)
    }

    // MARK: Actions and their animations

    private func perform(_ action: Action) {
        settleAnimations(announce: true)
        clearHighlight()
        if action == Action.deal, !game.state.canDeal {
            pointer.reset()
            if !game.state.stock.isEmpty, !game.state.isWon { alert = BoardAlert.info(GameModel.cannotDealMessage) }
            return
        }

        let animated: Bool = session.options.animationsEnabled
        let dealsBefore: Int = game.state.dealsRemaining
        var outcome: ActionOutcome? = nil
        var flightsStart: Double = 0

        if action == Action.deal {
            // No implicit animation: the dealt cards stay drawn on the pile they came from and
            // leave one by one below.
            pointer.reset()
            outcome = try? session.perform(action)
            if let outcome, animated {
                animations.beginDeal(outcome, dealsBefore: dealsBefore)
                animations.beginFlights(outcome.completedRuns, columns: game.state.columns)
                for (i, id) in outcome.dealtCardIDs.enumerated() {
                    schedule(Step.releaseDealt(id), after: BoardAnimations.dealStagger * Double(i))
                }
                flightsStart = BoardAnimations.dealStagger * Double(outcome.dealtCardIDs.count)
                    + BoardAnimations.dealDuration
            }
        } else {
            animate(Animation.easeOut(duration: 0.22)) {
                pointer.reset()
                outcome = try? session.perform(action)
                if let outcome, animated {
                    animations.beginFlights(outcome.completedRuns, columns: game.state.columns)
                }
            }
            flightsStart = 0.25
        }

        guard let outcome else { return }
        if outcome.didWin { persistStatistics() }
        guard animated else {
            announceEndState()
            return
        }
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
        case .newGame(let difficulty):
            requestNewGame(difficulty)
        case .request(let reason):
            requestAbandon(reason)
        case .present(let next):
            alert = next
        }
    }

    /// Win dialog or "no more moves" once the board has come to rest.
    private func announceEndState() {
        if game.state.isWon {
            alert = BoardAlert.won(score: game.state.score)
        } else if game.state.isStuck {
            alert = BoardAlert.noMoves
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

    /// `withAnimation` unless Options turned animations off.
    private func animate(_ animation: Animation, _ body: () -> Void) {
        if session.options.animationsEnabled {
            withAnimation(animation) { body() }
        } else {
            body()
        }
    }

    private func schedule(_ step: Step, after seconds: Double, cancellable: Bool = true) {
        let isHighlight: Bool
        if case .highlight = step { isHighlight = true } else { isHighlight = false }
        let generation: Int = isHighlight ? highlightGeneration : animationGeneration
        let nanoseconds: UInt64 = UInt64(max(0, seconds) * 1_000_000_000)
        // Created on the main actor, so the task body runs on the main actor too.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            if cancellable {
                let current: Int = isHighlight ? self.highlightGeneration : self.animationGeneration
                guard current == generation else { return }
            }
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
