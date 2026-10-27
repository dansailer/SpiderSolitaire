/// Achievements: a data-driven list (`Achievement.all`), the per-game facts they need
/// (`GameTracker`), the unlock record (`AchievementBook`, stored as achievements.json) and the
/// evaluator that turns game events into unlocks. Thresholds are documented in SPEC.md §7.
public enum AchievementID: String, Codable, Sendable, CaseIterable, Hashable {
    case firstWin, twoSuitWin, fourSuitWin
    case purist, noPeeking, grandmaster
    case speedster, efficient
    case cleanSweep, emptyHanded
    case hatTrick, onARoll
    case seasoned, century
}

/// What has to happen. Per-difficulty thresholds are keyed by `Difficulty`.
public enum AchievementRule: Sendable, Hashable {
    /// Win a game (at `difficulty`, or any when nil).
    case win(Difficulty?)
    /// Win without using Undo (at `difficulty`, or any when nil).
    case winWithoutUndo(Difficulty?)
    /// Win without asking for a hint.
    case winWithoutHints
    /// Win within this many seconds of play time.
    case winWithinSeconds([Difficulty: Int])
    /// Win with the Moves counter (moves, deals and undos) at or below this.
    case winWithinMoves([Difficulty: Int])
    /// Complete a suit while the stock is still full.
    case suitBeforeFirstDeal
    /// Empty a column while the stock is still full.
    case emptyColumnBeforeFirstDeal
    /// Current win streak at one difficulty reaches this.
    case winStreak(Int)
    /// Games won, all difficulties together.
    case gamesWon(Int)
    /// Games played (won or lost), all difficulties together.
    case gamesPlayed(Int)
}

/// The badge's emblem (drawn by `BadgeArt` in SpiderBoard).
public enum AchievementEmblem: String, Sendable, Hashable, CaseIterable {
    case star, twoPips, fourPips, laurel, closedEye, crown, clock, target, sweep, emptySlot
    case threeStars, flame, ribbon, hundred
}

public struct Achievement: Sendable, Hashable, Identifiable {
    public let id: AchievementID
    public let title: String
    /// Shown under the badge, locked or not.
    public let hint: String
    public let emblem: AchievementEmblem
    public let rule: AchievementRule

    public static let speedsterMinutes: [Difficulty: Int] = [.oneSuit: 5, .twoSuits: 12, .fourSuits: 25]
    public static let efficientMoves: [Difficulty: Int] = [.oneSuit: 150, .twoSuits: 200, .fourSuits: 300]

    public static let all: [Achievement] = [
        Achievement(id: .firstWin, title: "First Win", hint: "Win a game.", emblem: .star, rule: .win(nil)),
        Achievement(
            id: .twoSuitWin, title: "Two Suits", hint: "Win a game with two suits.",
            emblem: .twoPips, rule: .win(.twoSuits)),
        Achievement(
            id: .fourSuitWin, title: "Four Suits", hint: "Win a game with four suits.",
            emblem: .fourPips, rule: .win(.fourSuits)),
        Achievement(
            id: .purist, title: "Purist", hint: "Win a game without using Undo.",
            emblem: .laurel, rule: .winWithoutUndo(nil)),
        Achievement(
            id: .noPeeking, title: "No Peeking", hint: "Win a game without asking for a hint.",
            emblem: .closedEye, rule: .winWithoutHints),
        Achievement(
            id: .grandmaster, title: "Grandmaster", hint: "Win with four suits without using Undo.",
            emblem: .crown, rule: .winWithoutUndo(.fourSuits)),
        Achievement(
            id: .speedster, title: "Speedster",
            hint: "Win within 5 minutes (one suit), 12 (two suits) or 25 (four suits).",
            emblem: .clock, rule: .winWithinSeconds(speedsterMinutes.mapValues { $0 * 60 })),
        Achievement(
            id: .efficient, title: "Efficient",
            hint: "Win in at most 150 moves (one suit), 200 (two suits) or 300 (four suits).",
            emblem: .target, rule: .winWithinMoves(efficientMoves)),
        Achievement(
            id: .cleanSweep, title: "Clean Sweep", hint: "Complete a suit before the first deal.",
            emblem: .sweep, rule: .suitBeforeFirstDeal),
        Achievement(
            id: .emptyHanded, title: "Empty Handed", hint: "Empty a column before the first deal.",
            emblem: .emptySlot, rule: .emptyColumnBeforeFirstDeal),
        Achievement(
            id: .hatTrick, title: "Hat Trick", hint: "Win 3 games in a row at one difficulty.",
            emblem: .threeStars, rule: .winStreak(3)),
        Achievement(
            id: .onARoll, title: "On a Roll", hint: "Win 10 games in a row at one difficulty.",
            emblem: .flame, rule: .winStreak(10)),
        Achievement(id: .seasoned, title: "Seasoned", hint: "Win 25 games.", emblem: .ribbon, rule: .gamesWon(25)),
        Achievement(id: .century, title: "Century", hint: "Play 100 games.", emblem: .hundred, rule: .gamesPlayed(100)),
    ]

    public static func with(_ id: AchievementID) -> Achievement {
        all.first { $0.id == id }!
    }
}

/// Facts about the current game that the board does not keep. Saved with the game.
public struct GameTracker: Codable, Sendable, Hashable {
    /// Play time: counted by the app while it is active and the game is not won.
    public var elapsedSeconds: Double = 0
    public var undoCount = 0
    public var hintCount = 0
    /// False for a game resumed from a save written before achievements existed: its history is
    /// unknown, so the "without undo / hints / within N minutes" achievements are not awarded.
    public var isComplete = true

    public init() {}

    public static let unknownHistory: GameTracker = {
        var t = GameTracker()
        t.isComplete = false
        return t
    }()
}

/// Which achievements are unlocked, and when (seconds since 1970; the core has no Foundation).
public struct AchievementBook: Codable, Sendable, Hashable {
    public var unlocked: [AchievementID: Double] = [:]

    public init() {}

    public func isUnlocked(_ id: AchievementID) -> Bool { unlocked[id] != nil }

    // JSON as {"firstWin": 1767225600, ...}; unknown names (from a newer version) are kept out
    // without failing the whole file.
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys {
            guard let id = AchievementID(rawValue: key.stringValue),
                let date = try? container.decode(Double.self, forKey: key)
            else { continue }
            unlocked[id] = date
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (id, date) in unlocked {
            try container.encode(date, forKey: Key(stringValue: id.rawValue))
        }
    }
}

/// Something that happened, as the evaluator sees it.
public enum AchievementEvent: Sendable, Hashable {
    /// A card move or deal was performed (`state` is the position after it).
    case played
    /// A result went into the statistics (win, or a loss from abandoning / quitting).
    case resultRecorded
}

public enum AchievementEvaluator {
    /// Achievements that `event` satisfies and `book` does not have yet, in `Achievement.all` order.
    public static func newlyUnlocked(
        by event: AchievementEvent, state: GameState, tracker: GameTracker,
        statistics: Statistics, book: AchievementBook
    ) -> [AchievementID] {
        Achievement.all.filter { achievement in
            !book.isUnlocked(achievement.id)
                && isMet(achievement.rule, by: event, state: state, tracker: tracker, statistics: statistics)
        }.map(\.id)
    }

    static func isMet(
        _ rule: AchievementRule, by event: AchievementEvent, state: GameState,
        tracker: GameTracker, statistics: Statistics
    ) -> Bool {
        let difficulty = state.difficulty
        let won = event == .played && state.isWon
        let stockFull = state.stock.count == GameState.fullStockCount
        switch rule {
        case .win(let d):
            return won && (d == nil || d == difficulty)
        case .winWithoutUndo(let d):
            return won && tracker.isComplete && tracker.undoCount == 0 && (d == nil || d == difficulty)
        case .winWithoutHints:
            return won && tracker.isComplete && tracker.hintCount == 0
        case .winWithinSeconds(let limits):
            guard won, tracker.isComplete, let limit = limits[difficulty] else { return false }
            return tracker.elapsedSeconds < Double(limit)
        case .winWithinMoves(let limits):
            guard won, let limit = limits[difficulty] else { return false }
            return state.moves <= limit
        case .suitBeforeFirstDeal:
            return event == .played && stockFull && !state.completed.isEmpty
        case .emptyColumnBeforeFirstDeal:
            return event == .played && stockFull && state.columns.contains { $0.isEmpty }
        case .winStreak(let n):
            return event == .resultRecorded && Difficulty.allCases.contains { statistics[$0].currentWinStreak >= n }
        case .gamesWon(let n):
            return event == .resultRecorded && Difficulty.allCases.reduce(0) { $0 + statistics[$1].won } >= n
        case .gamesPlayed(let n):
            return event == .resultRecorded && Difficulty.allCases.reduce(0) { $0 + statistics[$1].played } >= n
        }
    }
}
