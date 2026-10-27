/// A game plus its bookkeeping, exactly what savedgame.json holds.
public struct SavedSession: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int = SavedSession.currentVersion
    /// The full game, including its undo history.
    public var game: SpiderGame
    /// True once this game's win or loss is in the statistics, so it is never counted twice.
    public var resultRecorded: Bool = false
    /// Play time, undo and hint counts for achievements.
    public var tracker: GameTracker = GameTracker()

    public init(game: SpiderGame, resultRecorded: Bool = false) {
        self.game = game
        self.resultRecorded = resultRecorded
    }

    private enum CodingKeys: String, CodingKey {
        case version, game, resultRecorded, tracker
    }

    /// Saves from before achievements have no tracker: their history is unknown.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        game = try c.decode(SpiderGame.self, forKey: .game)
        resultRecorded = try c.decode(Bool.self, forKey: .resultRecorded)
        tracker = try c.decodeIfPresent(GameTracker.self, forKey: .tracker) ?? GameTracker.unknownHistory
    }

    /// Started (at least one move or deal), not won, not yet counted: quitting it is a loss.
    public var isInProgress: Bool {
        game.state.moves > 0 && !game.state.isWon && !resultRecorded
    }
}

/// Why the current game is being replaced.
public enum AbandonReason: Hashable, Sendable {
    case newGame(Difficulty)
    case restart
    case openSavedGame
}

/// What to do with the current game when the app quits.
public enum QuitDecision: Hashable, Sendable {
    /// Nothing worth saving (not started, won, or already counted).
    case nothing
    case save
    /// Options say never save: the game is abandoned and counts as a loss.
    case discardAsLoss
    /// Ask "Do you want to save this game?"
    case ask
}

/// What to do at launch.
public enum LaunchDecision: Hashable, Sendable {
    case newGame
    case resumeSaved
    /// Ask "Do you want to open your saved game?"
    case ask
    /// Options say never open: the saved game is dropped and, if it was in progress, counts as a loss.
    case discardSaved
}

/// Every rule about game lifecycle and statistics, with no I/O. The app does the file reads and
/// writes and asks this type what should happen.
public struct SessionController: Sendable {
    public private(set) var session: SavedSession
    public private(set) var statistics: Statistics
    public private(set) var achievements: AchievementBook
    /// Unlocked since the last `commitUnlocks`, in order (the app dates, stores and announces them).
    public private(set) var pendingUnlocks: [AchievementID] = []
    public var options: Options {
        didSet { session.game.undoPolicy = options.undoPolicy }
    }

    public var game: SpiderGame { session.game }

    public init(options: Options, statistics: Statistics, achievements: AchievementBook = AchievementBook(),
                seed: UInt64) {
        self.options = options
        self.statistics = statistics
        self.achievements = achievements
        session = SavedSession(game: SpiderGame(difficulty: options.difficulty, seed: seed, undoPolicy: options.undoPolicy))
    }

    // MARK: Lifecycle

    /// Replacing the game now would abandon a game in progress, so ask first.
    public var needsAbandonConfirmation: Bool { session.isInProgress }

    /// New deal at `difficulty` (also remembered as the default). Counts the old game as a loss if it was in progress.
    public mutating func startNewGame(difficulty: Difficulty, seed: UInt64) {
        recordLossIfInProgress()
        options.difficulty = difficulty
        session = SavedSession(game: SpiderGame(difficulty: difficulty, seed: seed, undoPolicy: options.undoPolicy))
    }

    /// Same deal again from the start (same seed and difficulty). Counts as a loss if in progress.
    public mutating func restart() {
        let state = session.game.state
        recordLossIfInProgress()
        session = SavedSession(game: SpiderGame(difficulty: state.difficulty, seed: state.seed, undoPolicy: options.undoPolicy))
    }

    /// Continue a saved game (⌘O, or resume at launch). The current game counts as a loss if in progress.
    public mutating func open(_ saved: SavedSession) {
        recordLossIfInProgress()
        var saved = saved
        saved.game.undoPolicy = options.undoPolicy
        session = saved
    }

    /// The player declined a saved game at launch (or options say never open): it is abandoned.
    public mutating func discard(_ saved: SavedSession) {
        guard saved.isInProgress else { return }
        statistics[saved.game.state.difficulty].recordLoss()
        evaluate(.resultRecorded, state: saved.game.state, tracker: saved.tracker)
    }

    // MARK: Play

    @discardableResult
    public mutating func perform(_ action: Action) throws -> ActionOutcome {
        let outcome = try session.game.perform(action)
        return recordPlayed(outcome)
    }

    public var canRedo: Bool { session.game.canRedo }

    /// Redo the last undone action (scored and counted like a move).
    @discardableResult
    public mutating func redo() throws -> ActionOutcome {
        let outcome = try session.game.redo()
        return recordPlayed(outcome)
    }

    private mutating func recordPlayed(_ outcome: ActionOutcome) -> ActionOutcome {
        evaluate(.played)
        if outcome.didWin, !session.resultRecorded {
            statistics[session.game.state.difficulty].recordWin(score: session.game.state.score)
            session.resultRecorded = true
            evaluate(.resultRecorded)
        }
        return outcome
    }

    /// Undo is not offered once the game is won (its result is already counted).
    public var canUndo: Bool { session.game.canUndo && !session.game.state.isWon }

    public mutating func undo() throws {
        guard !session.game.state.isWon else { throw GameError.gameOver }
        try session.game.undo()
        session.tracker.undoCount += 1
    }

    // MARK: Achievements and play time

    /// A hint was shown (counts against No Peeking).
    public mutating func noteHint() {
        session.tracker.hintCount += 1
    }

    /// The game clock runs while the game is not won (the app pauses it when inactive).
    public var isClockRunning: Bool { !session.game.state.isWon && !session.resultRecorded }

    public mutating func addPlayTime(_ seconds: Double) {
        guard isClockRunning, seconds > 0 else { return }
        session.tracker.elapsedSeconds += seconds
    }

    /// Dates the pending unlocks (seconds since 1970), adds them to `achievements` and returns them.
    public mutating func commitUnlocks(at date: Double) -> [AchievementID] {
        let unlocked = pendingUnlocks
        pendingUnlocks = []
        for id in unlocked where !achievements.isUnlocked(id) { achievements.unlocked[id] = date }
        return unlocked
    }

    private mutating func evaluate(_ event: AchievementEvent) {
        evaluate(event, state: session.game.state, tracker: session.tracker)
    }

    private mutating func evaluate(_ event: AchievementEvent, state: GameState, tracker: GameTracker) {
        var book = achievements
        for id in pendingUnlocks { book.unlocked[id] = 0 }
        pendingUnlocks += AchievementEvaluator.newlyUnlocked(by: event, state: state, tracker: tracker,
                                                             statistics: statistics, book: book)
    }

    // MARK: Quit and launch

    public var quitDecision: QuitDecision {
        guard session.isInProgress else { return .nothing }
        switch options.saveOnExit {
        case .always: return .save
        case .never: return .discardAsLoss
        case .prompt: return .ask
        }
    }

    /// Player chose not to save at quit (or options say never): the game counts as a loss.
    public mutating func quitWithoutSaving() {
        recordLossIfInProgress()
    }

    public static func launchDecision(options: Options, hasSavedGame: Bool) -> LaunchDecision {
        guard hasSavedGame else { return .newGame }
        switch options.openOnStart {
        case .always: return .resumeSaved
        case .never: return .discardSaved
        case .prompt: return .ask
        }
    }

    // MARK: Statistics

    public mutating func resetStatistics(_ difficulty: Difficulty) {
        statistics.reset(difficulty)
    }

    private mutating func recordLossIfInProgress() {
        guard session.isInProgress else { return }
        statistics[session.game.state.difficulty].recordLoss()
        session.resultRecorded = true
        evaluate(.resultRecorded)
    }
}
