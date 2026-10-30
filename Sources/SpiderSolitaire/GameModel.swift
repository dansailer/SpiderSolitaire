#if canImport(SwiftUI)
import Foundation
import SpiderBoard
import SpiderCore
import SpiderPersistence
import AppKit
import SwiftUI

/// The one dialog the board can show at a time (a single `.alert` drives all of them).
enum BoardAlert: Identifiable, Sendable {
    case info(String)
    case noMoves
    case confirmAbandon(AbandonReason)
    case openSavedGame

    var id: String {
        switch self {
        case .info(let text): return "info:" + text
        case .noMoves: return "noMoves"
        case .confirmAbandon: return "abandon"
        case .openSavedGame: return "openSaved"
        }
    }

    var title: String { "Spider Solitaire" }

    var message: String {
        switch self {
        case .info(let text): return text
        case .noMoves: return loc("There are no more moves.")
        case .confirmAbandon:
            return loc("This game is in progress and will count as a loss. Do you want to quit this game?")
        case .openSavedGame: return loc("Do you want to open your previously saved game?")
        }
    }
}

extension GameModel {
    /// XP's message when a deal is refused.
    static var cannotDealMessage: String {
        loc("You are not allowed to deal a new row while there are any empty slots.")
    }
}

/// Glue between SwiftUI and the pure modules. Holds no rules: SessionController owns the game
/// lifecycle and statistics, SpiderGame the rules, PointerController the gestures, BoardLayout
/// the geometry, BoardAnimations / HintCycler the animation and hint state, SpiderStore the files.
/// This class sequences those in time and wraps them in `withAnimation`.
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var session: SessionController
    @Published private(set) var pointer: PointerController = PointerController()
    @Published private(set) var animations: BoardAnimations = BoardAnimations()
    @Published private(set) var highlight: HintHighlight?
    @Published private(set) var hasSavedGame: Bool = false
    @Published var alert: BoardAlert?
    @Published var showStatisticsSheet: Bool = false
    /// The win animation (nil when none). The view samples it every frame while it runs, and
    /// keeps its last frame under the win panel once it has stopped.
    @Published private(set) var celebration: Celebration?
    /// The win panel ("You win!") over the finished board (nil when none).
    @Published private(set) var winSummary: WinSummary?
    /// Set while a winnable deal is being searched for (the board shows "Dealing a winnable game…").
    @Published private(set) var dealingDifficulty: Difficulty?
    /// The achievement banner at the top of the board (nil when none).
    @Published private(set) var toast: Achievement?

    struct Celebration: Sendable {
        let show: WinCelebration
        let start: Date
        /// Show time at which it stopped (it ended, or a click or key skipped it); nil while running.
        var stoppedAt: Double?
    }

    private let store: SpiderStore
    private var hintCycler: HintCycler = HintCycler()
    /// Bumped to cancel scheduled animation steps (any new action settles running animations).
    private var animationGeneration: Int = 0
    /// A click that skipped a running deal: the rest of that gesture is ignored, so it cannot
    /// also pick up or move a card that was still in the air.
    private var suppressedGesture: GestureSuppression = GestureSuppression()
    /// Bumped to cancel a running hint flash.
    private var highlightGeneration: Int = 0
    /// Identifies the current celebration so a stale end step does nothing.
    private var celebrationID: Int = 0
    /// The win has been celebrated / announced for this game.
    private var winAnnounced: Bool = false

    /// Winnable seeds found ahead of time (winnable.json) and the searches that fill it.
    private var seedCache: WinnableSeedCache
    private var dealTask: Task<Void, Never>?
    private var dealGeneration: Int = 0
    private var prefillTask: Task<Void, Never>?
    private var prefillGeneration: Int = 0
    /// Achievements waiting for their banner, and the banner on screen.
    private var toastQueue: [Achievement] = []
    private var toastID: Int = 0
    /// Game clock: ticks once a second; play time only counts while the app is active.
    private var clockTask: Task<Void, Never>?
    private var lastTick: Double = ProcessInfo.processInfo.systemUptime

    /// One timed step of an animation, hint flash or deferred request.
    private enum Step: Sendable {
        /// A dealt card leaves the stock, with the deal click.
        case releaseDealt(Int)
        /// A dealt card reached its column (the deal is over once the last one has).
        case landDealt(Int)
        case land(Int)
        case finishSlot(Int)
        case afterAnimations
        case highlight(HintHighlight?)
        case newGame(Difficulty)
        /// Alert buttons that lead to another alert run after the first one has gone away.
        case request(AbandonReason)
        case present(BoardAlert)
        case endCelebration(Int)
        case hideToast(Int)
        case nextToast
    }

    init(store: SpiderStore = SpiderStore.standard()) {
        self.store = store
        let options: Options = store.loadOptions()
        session = SessionController(
            options: options, statistics: store.loadStatistics(),
            achievements: store.loadAchievements(), seed: GameModel.randomSeed())
        seedCache = store.loadWinnableSeeds()

        switch SessionController.launchDecision(options: options, hasSavedGame: store.hasSavedGame) {
        case .newGame:
            // The launch deal is random; with winnable deals on, replace it before it is played.
            if options.winnableDealsOnly {
                schedule(Step.newGame(options.difficulty), after: 0, cancellable: false)
            } else {
                animateInitialDeal(delay: GameModel.launchDealDelay)
            }
        case .resumeSaved:
            if let saved: SavedSession = store.takeSavedGame() { session.open(saved) }
        case .discardSaved:
            if let saved: SavedSession = store.takeSavedGame() { session.discard(saved) }
            animateInitialDeal(delay: GameModel.launchDealDelay)
        case .ask:
            alert = BoardAlert.openSavedGame
        }
        hasSavedGame = store.hasSavedGame
        persistStatistics()
        collectUnlocks()
        startClock()
    }

    /// At launch the window appears just after the model is made; start the deal once it is up.
    static let launchDealDelay: Double = 0.35

    nonisolated static func randomSeed() -> UInt64 { UInt64.random(in: UInt64.min...UInt64.max) }

    var game: SpiderGame { session.game }
    var options: Options { session.options }
    var statistics: Statistics { session.statistics }
    var achievements: AchievementBook { session.achievements }
    var canUndo: Bool { session.canUndo }
    var canRedo: Bool { session.canRedo }
    /// Dealt cards are still on their way from the stock (a click or key skips to the end).
    var isDealing: Bool { animations.isDealing }

    /// Deals animate when Settings → Show animations is on and macOS Reduce Motion is off.
    private var dealsAnimate: Bool {
        session.options.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: Game menu

    /// New Game (⌘N), Game ▸ Difficulty (⌘1 / ⌘2 / ⌘4). `nil` keeps the current difficulty.
    func requestNewGame(_ difficulty: Difficulty?) {
        requestAbandon(AbandonReason.newGame(difficulty ?? game.state.difficulty))
    }

    func requestRestart() {
        requestAbandon(AbandonReason.restart)
    }

    func requestOpenSavedGame() {
        guard store.hasSavedGame else {
            hasSavedGame = false
            alert = BoardAlert.info(loc("There is no saved game."))
            return
        }
        requestAbandon(AbandonReason.openSavedGame)
    }

    func saveGame() {
        do {
            try store.saveGame(session.session)
            hasSavedGame = true
            alert = BoardAlert.info(loc("Your game has been saved."))
        } catch {
            alert = BoardAlert.info(loc("The game could not be saved: %@", error.localizedDescription))
        }
    }

    func applyOptions(_ options: Options) {
        session.options = options
        persistOptions()
        if options.winnableDealsOnly { prefillWinnableSeeds(options.difficulty) }
    }

    /// `--snapshot` (website screenshots): a bundled winnable deal, played `moves` steps along the
    /// solver's winning line, without animation.
    func prepareSnapshot(difficulty: Difficulty, moves: Int) {
        resetTransientState()
        let seed: UInt64 = WinnableDeals.bundled[difficulty]?.first ?? 1
        session.startNewGame(difficulty: difficulty, seed: seed)
        let line: [Action] = Solver.winningLine(difficulty: difficulty, seed: seed) ?? []
        for action in line.prefix(moves) {
            _ = try? session.perform(action)
        }
        alert = nil
    }

    /// `--snapshot --win-frames`: the bundled deal played to its win, which is then announced as
    /// after a real winning move (the celebration, or the win panel straight away).
    func prepareWinSnapshot(difficulty: Difficulty) {
        prepareSnapshot(difficulty: difficulty, moves: Int.max)
        announceEndState()
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
                animateInitialDeal()
            }
        }
        hasSavedGame = store.hasSavedGame
        persistStatistics()
        collectUnlocks()
    }

    func deal() {
        perform(Action.deal)
    }

    /// Redo (⇧⌘Z): plays the last undone action again, with the usual animations.
    func redo() {
        guard let action: Action = game.nextRedo, session.canRedo else { return }
        perform(action, redo: true)
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
        _ = session.commitUnlocks(at: Date().timeIntervalSince1970)
        persistAchievements()
    }

    // MARK: Hints

    /// Game ▸ Show Hint (⌘T) / click on the score box: flash the next hint (source run, then target).
    func showHint() {
        settleAnimations(announce: true)
        guard !game.state.isWon else { return }
        let step: HintStep = hintCycler.next(for: game.state)
        let sequence: [HintHighlight] = HintHighlight.sequence(for: step)
        guard !sequence.isEmpty else {
            clearHighlight()
            play(SoundCue.noMoves)
            alert = BoardAlert.noMoves
            return
        }
        play(SoundCue.hint)
        session.noteHint()
        highlightGeneration += 1
        highlight = sequence[0]
        for i in 1..<(sequence.count + 1) {
            let next: HintHighlight? = i < sequence.count ? sequence[i] : nil
            schedule(Step.highlight(next), after: HintHighlight.beat * Double(i))
        }
    }

    // MARK: Pointer (one DragGesture with minimumDistance 0 drives everything)

    func pointerChanged(start: CGPoint, translation: CGSize, layout: BoardLayout) {
        guard celebration == nil, winSummary == nil else { return }
        if suppressedGesture.ignoresChange(start: BoardPoint(start)) { return }
        if animations.isDealing {
            // First click during a deal (until its last card has landed) finishes it at once
            // and does nothing else.
            skipDeal()
            suppressedGesture.suppress(start: BoardPoint(start))
            return
        }
        if !animations.isIdle { settleAnimations(announce: true) }
        if highlight != nil { clearHighlight() }
        var next: PointerController = pointer
        next.pointerChanged(
            start: BoardPoint(start), translation: BoardSize(translation), state: game.state, layout: layout)
        pointer = next
    }

    func pointerEnded(start: CGPoint, translation: CGSize, layout: BoardLayout) {
        if celebration != nil {
            skipCelebration()
            return
        }
        if winSummary != nil { return }
        if suppressedGesture.ignoresEnd(start: BoardPoint(start)) { return }
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
        cancelWinnableSearch()
        if case .newGame(let difficulty) = reason, session.options.winnableDealsOnly {
            // The current game stays (and is counted) until the new deal is ready.
            dealWinnableGame(difficulty)
            return
        }
        resetTransientState()
        switch reason {
        case .newGame(let difficulty):
            session.startNewGame(difficulty: difficulty, seed: GameModel.randomSeed())
            persistOptions()
            animateInitialDeal()
        case .restart:
            session.restart()
            animateInitialDeal()
        case .openSavedGame:
            if let saved: SavedSession = store.takeSavedGame() {
                session.open(saved)
            } else {
                schedule(
                    Step.present(BoardAlert.info(loc("The saved game could not be opened."))), after: 0.3,
                    cancellable: false
                )
            }
            hasSavedGame = store.hasSavedGame
        }
        persistStatistics()
        collectUnlocks()
    }

    // MARK: Winnable deals

    /// Cancel button on the "Dealing a winnable game…" panel: deal an unchecked game instead.
    func cancelWinnableDeal() {
        guard let difficulty = dealingDifficulty else { return }
        cancelWinnableSearch()
        startDeal(difficulty, seed: GameModel.randomSeed())
    }

    /// A cached seed starts at once; otherwise search in the background for up to
    /// `WinnableDeals.searchSeconds`, then fall back to a bundled seed (or, if there is none, a
    /// random deal with a notice).
    private func dealWinnableGame(_ difficulty: Difficulty) {
        if let seed: UInt64 = seedCache.takeReady(difficulty) {
            persistSeedCache()
            startDeal(difficulty, seed: seed)
            prefillWinnableSeeds(difficulty)
            return
        }
        stopPrefill()
        dealGeneration += 1
        let generation: Int = dealGeneration
        dealingDifficulty = difficulty
        let seconds: Double = WinnableDeals.searchSeconds
        dealTask = Task.detached(priority: TaskPriority.userInitiated) { [weak self] in
            let clock: ContinuousClock = ContinuousClock()
            let deadline: ContinuousClock.Instant = clock.now.advanced(by: Duration.milliseconds(Int64(seconds * 1000)))
            let seed: UInt64? = WinnableDeals.search(
                difficulty: difficulty, nextSeed: { GameModel.randomSeed() },
                shouldStop: { Task.isCancelled || clock.now >= deadline })
            await self?.finishWinnableSearch(generation: generation, difficulty: difficulty, seed: seed)
        }
    }

    private func finishWinnableSearch(generation: Int, difficulty: Difficulty, seed: UInt64?) {
        guard generation == dealGeneration, dealingDifficulty != nil else { return }
        dealTask = nil
        dealingDifficulty = nil
        if let seed {
            startDeal(difficulty, seed: seed)
        } else if let bundled: UInt64 = seedCache.takeBundled(difficulty) {
            persistSeedCache()
            startDeal(difficulty, seed: bundled)
        } else {
            startDeal(difficulty, seed: GameModel.randomSeed())
            schedule(
                Step.present(BoardAlert.info(loc("No winnable deal was found in time, so this is a random deal."))),
                after: 0.3, cancellable: false)
        }
        prefillWinnableSeeds(difficulty)
    }

    private func cancelWinnableSearch() {
        dealGeneration += 1
        dealTask?.cancel()
        dealTask = nil
        dealingDifficulty = nil
    }

    private func startDeal(_ difficulty: Difficulty, seed: UInt64) {
        resetTransientState()
        session.startNewGame(difficulty: difficulty, seed: seed)
        animateInitialDeal()
        persistOptions()
        persistStatistics()
        collectUnlocks()
    }

    /// The 54 cards of a fresh game fly from the stock to the columns one after another
    /// (`DealPacing.initial`). The game state is already complete; only the drawing lags, so
    /// skipping, undo and saving never see a half-dealt game.
    private func animateInitialDeal(delay: Double = 0) {
        guard dealsAnimate else { return }
        animations.beginInitialDeal(game.state)
        scheduleDeal(DealPacing.Kind.initial, ids: animations.dealHold?.waitingIDs ?? [], delay: delay)
    }

    /// Every card of a deal leaves the stock (with its click) and later lands, at its own time.
    private func scheduleDeal(_ kind: DealPacing.Kind, ids: [Int], delay: Double = 0) {
        for step in DealPacing.steps(kind, ids: ids, delay: delay) {
            schedule(Step.releaseDealt(step.id), after: step.release)
            schedule(Step.landDealt(step.id), after: step.landing)
        }
    }

    /// Click or key press during a deal: every card lands at once.
    func skipDeal() {
        guard animations.isDealing else { return }
        settleAnimations(announce: true)
    }

    /// Keeps `WinnableDeals.cacheTarget` seeds ready so the next winnable deal is instant.
    private func prefillWinnableSeeds(_ difficulty: Difficulty) {
        guard prefillTask == nil, dealTask == nil, seedCache.count(difficulty) < WinnableDeals.cacheTarget else {
            return
        }
        prefillGeneration += 1
        let generation: Int = prefillGeneration
        prefillTask = Task.detached(priority: TaskPriority.background) { [weak self] in
            let clock: ContinuousClock = ContinuousClock()
            let deadline: ContinuousClock.Instant = clock.now.advanced(by: Duration.seconds(60))
            let seed: UInt64? = WinnableDeals.search(
                difficulty: difficulty, nextSeed: { GameModel.randomSeed() },
                shouldStop: { Task.isCancelled || clock.now >= deadline })
            await self?.finishPrefill(generation: generation, difficulty: difficulty, seed: seed)
        }
    }

    private func finishPrefill(generation: Int, difficulty: Difficulty, seed: UInt64?) {
        guard generation == prefillGeneration else { return }
        prefillTask = nil
        guard let seed else { return }
        seedCache.add(seed, for: difficulty)
        persistSeedCache()
        if session.options.winnableDealsOnly { prefillWinnableSeeds(difficulty) }
    }

    private func stopPrefill() {
        prefillGeneration += 1
        prefillTask?.cancel()
        prefillTask = nil
    }

    private func persistSeedCache() {
        try? store.saveWinnableSeeds(seedCache)
    }

    // MARK: Achievements

    /// Dates and stores new unlocks and queues their banners.
    private func collectUnlocks() {
        let unlocked: [AchievementID] = session.commitUnlocks(at: Date().timeIntervalSince1970)
        guard !unlocked.isEmpty else { return }
        persistAchievements()
        // The win panel lists what the winning move unlocked; no banner over the celebration.
        guard !game.state.isWon else { return }
        toastQueue += unlocked.map { (id: AchievementID) -> Achievement in Achievement.with(id) }
        if toast == nil { showNextToast() }
    }

    private func showNextToast() {
        guard toast == nil, !toastQueue.isEmpty else { return }
        let next: Achievement = toastQueue.removeFirst()
        toastID += 1
        animate(Animation.spring(response: 0.45, dampingFraction: 0.85)) {
            toast = next
        }
        play(SoundCue.achievement)
        schedule(Step.hideToast(toastID), after: 3.2, cancellable: false)
    }

    /// Click on the banner: dismiss it now.
    func dismissToast() {
        apply(Step.hideToast(toastID))
    }

    private func persistAchievements() {
        try? store.saveAchievements(session.achievements)
    }

    // MARK: Game clock

    /// Play time shown in the score box.
    var elapsedSeconds: Int { Int(session.session.tracker.elapsedSeconds) }

    private func startClock() {
        lastTick = ProcessInfo.processInfo.systemUptime
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let now: Double = ProcessInfo.processInfo.systemUptime
        let delta: Double = min(now - lastTick, 2)
        lastTick = now
        guard NSApplication.shared.isActive, session.isClockRunning, dealingDifficulty == nil, celebration == nil,
            alert == nil, !showStatisticsSheet
        else { return }
        session.addPlayTime(delta)
    }

    private func resetTransientState() {
        celebration = nil
        winSummary = nil
        celebrationID += 1
        winAnnounced = false
        settleAnimations(announce: false)
        suppressedGesture.reset()
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

    private func perform(_ action: Action, redo: Bool = false) {
        settleAnimations(announce: true)
        clearHighlight()
        if action == Action.deal, !game.state.canDeal {
            pointer.reset()
            if !game.state.stock.isEmpty, !game.state.isWon {
                play(SoundCue.cannotDeal)
                alert = BoardAlert.info(GameModel.cannotDealMessage)
            }
            return
        }

        let animated: Bool = action == Action.deal ? dealsAnimate : session.options.animationsEnabled
        let dealsBefore: Int = game.state.dealsRemaining
        var outcome: ActionOutcome?
        var flightsStart: Double = 0

        if action == Action.deal {
            // No implicit animation: the dealt cards stay drawn on the pile they came from and
            // leave one by one below.
            pointer.reset()
            outcome = try? (redo ? session.redo() : session.perform(action))
            if let outcome, animated {
                animations.beginDeal(outcome, dealsBefore: dealsBefore)
                animations.beginFlights(outcome.completedRuns, columns: game.state.columns)
                // Released in column order. A card the deal completed into a run is not waiting
                // (it flies to the foundation; releasing it does nothing) but keeps its step, so
                // all ten cards click in rhythm.
                scheduleDeal(DealPacing.Kind.stock, ids: outcome.dealtCardIDs)
                flightsStart = DealPacing.totalDuration(DealPacing.Kind.stock, cards: outcome.dealtCardIDs.count)
            }
        } else {
            animate(Animation.easeOut(duration: 0.22)) {
                pointer.reset()
                outcome = try? (redo ? session.redo() : session.perform(action))
                if let outcome, animated {
                    animations.beginFlights(outcome.completedRuns, columns: game.state.columns)
                }
            }
            flightsStart = 0.25
        }

        guard let outcome else { return }
        collectUnlocks()
        // An animated deal clicks with each card (`Step.releaseDealt`).
        if action != Action.deal {
            play(SoundCue.drop)
        } else if !animated {
            play(SoundCue.deal)
        }
        if !outcome.completedRuns.isEmpty { play(SoundCue.completedSuit) }
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
            withAnimation(Animation.easeOut(duration: DealPacing.flightDuration)) {
                _ = animations.releaseDealtCard(id)
            }
            play(SoundCue.deal)
        case .landDealt(let id):
            // Not animated: a card dealt face up turns over at once as it lands.
            _ = animations.landDealtCard(id)
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
        case .endCelebration(let id):
            if id == celebrationID, isCelebrating { finishCelebration(fade: WinPanelTiming.afterShow) }
        case .hideToast(let id):
            guard id == toastID, toast != nil else { return }
            animate(Animation.easeIn(duration: 0.3)) {
                toast = nil
            }
            schedule(Step.nextToast, after: 0.45, cancellable: false)
        case .nextToast:
            showNextToast()
        }
    }

    /// Win celebration (then dialog) or "no more moves" once the board has come to rest.
    private func announceEndState() {
        if game.state.isWon {
            guard !winAnnounced else { return }
            winAnnounced = true
            play(SoundCue.win)
            if dealsAnimate {
                celebrationID += 1
                let show: WinCelebration = WinCelebration(suits: game.state.completed, seed: game.state.seed)
                celebration = Celebration(show: show, start: Date())
                schedule(Step.endCelebration(celebrationID), after: show.endTime, cancellable: false)
            } else {
                // Reduce Motion: a calm cross-fade to the panel; animations off: at once.
                showWinSummary(fade: session.options.animationsEnabled ? WinPanelTiming.reduceMotion : nil)
            }
        } else if game.state.isStuck {
            play(SoundCue.noMoves)
            alert = BoardAlert.noMoves
        }
    }

    private func play(_ cue: SoundCue) {
        guard session.options.soundsEnabled else { return }
        SoundPlayer.play(cue)
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

// MARK: - Win celebration and win panel

extension GameModel {
    /// The win animation is running (a click or any key skips to the win panel).
    var isCelebrating: Bool { celebration != nil && celebration?.stoppedAt == nil }

    /// Click or key press during the win animation: stop it and show the win panel.
    func skipCelebration() {
        guard isCelebrating else { return }
        finishCelebration(fade: WinPanelTiming.afterSkip)
    }

    private func finishCelebration(fade: Double) {
        guard var current: Celebration = celebration else { return }
        celebrationID += 1
        current.stoppedAt = min(Date().timeIntervalSince(current.start), current.show.endTime)
        celebration = current
        showWinSummary(fade: fade)
    }

    private func showWinSummary(fade: Double?) {
        guard let summary: WinSummary = session.winSummary else { return }
        if let fade {
            withAnimation(Animation.easeInOut(duration: fade)) { winSummary = summary }
        } else {
            winSummary = summary
        }
    }

    /// Win panel ▸ Close: back to the finished board (the piles return to the foundation).
    func closeWinSummary() {
        animate(Animation.easeOut(duration: 0.25)) {
            winSummary = nil
            celebration = nil
        }
    }

    /// Win panel ▸ Play Again: a new game at the same difficulty (a won game needs no confirmation).
    func playAgain() {
        winSummary = nil
        celebration = nil
        requestNewGame(nil)
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
