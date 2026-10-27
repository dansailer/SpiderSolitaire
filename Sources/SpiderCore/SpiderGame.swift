/// What the player can ask the engine to do.
public enum Action: Codable, Sendable, Hashable {
    /// Move the cards from `index` to the top of column `from` onto column `to`.
    case move(from: Int, index: Int, to: Int)
    /// Deal one card onto every column from the stock.
    case deal
}

/// A K..A run that was removed to the foundation.
public struct CompletedRun: Sendable, Hashable {
    public let column: Int
    public let suit: Suit
    /// The 13 removed cards, King first (bottom of the run) to Ace (top), for the fly-off animation.
    public let cards: [Card]
    /// Foundation slot the run went to (0 = first completed suit).
    public let foundationSlot: Int

    public init(column: Int, suit: Suit, cards: [Card] = [], foundationSlot: Int = 0) {
        self.column = column
        self.suit = suit
        self.cards = cards
        self.foundationSlot = foundationSlot
    }
}

/// Side effects of an action, for the UI to animate (flip, fly to foundation, deal sweep).
public struct ActionOutcome: Sendable, Hashable {
    /// Runs removed by this action, in removal order.
    public var completedRuns: [CompletedRun] = []
    /// Ids of cards turned face up by this action (not counting dealt cards).
    public var revealedCardIDs: [Int] = []
    /// Ids of the cards a deal put on the columns, in column order (empty for moves). Cards that a
    /// deal immediately completed into a run are included too.
    public var dealtCardIDs: [Int] = []
    public var didWin = false
}

public enum GameError: Error, Equatable, Sendable {
    case illegalMove
    case cannotDealWithEmptyColumn
    case stockEmpty
    case nothingToUndo
    case nothingToRedo
    case gameOver
}

/// How far back undo may go.
public enum UndoPolicy: String, Codable, Sendable, CaseIterable {
    /// Back to the start of the game (the brief's requirement, and Vista+ behaviour).
    case unlimited
    /// Original XP: a deal or a completed-suit removal clears the undo history.
    case xpClassic
}

/// Scoring constants. Defaults are XP's.
public struct ScoringRules: Codable, Sendable, Hashable {
    public var movePenalty = 1
    public var undoPenalty = 1
    public var completedSuitBonus = 100
    /// XP does not charge for a deal.
    public var dealPenalty = 0

    public init() {}
}

/// The rules engine: owns the current `GameState` plus the undo history.
public struct SpiderGame: Codable, Sendable {
    public private(set) var state: GameState
    public var undoPolicy: UndoPolicy
    public var scoring: ScoringRules

    private struct UndoEntry: Codable, Sendable {
        var before: GameState
        /// Penalty charged by the undone action; it is not refunded by undo.
        var penaltyCharged: Int
        /// The action itself, for redo (nil in saves from before redo existed).
        var action: Action?
    }
    private var undoStack: [UndoEntry] = []
    /// Undone actions, most recent last. Any new action clears it.
    private var redoStack: [Action] = []

    private enum CodingKeys: String, CodingKey {
        case state, undoPolicy, scoring, undoStack, redoStack
    }

    /// Saves from before redo have no `redoStack`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(GameState.self, forKey: .state)
        undoPolicy = try c.decode(UndoPolicy.self, forKey: .undoPolicy)
        scoring = try c.decode(ScoringRules.self, forKey: .scoring)
        undoStack = try c.decode([UndoEntry].self, forKey: .undoStack)
        redoStack = try c.decodeIfPresent([Action].self, forKey: .redoStack) ?? []
    }

    public init(difficulty: Difficulty, seed: UInt64, undoPolicy: UndoPolicy = .unlimited,
                scoring: ScoringRules = ScoringRules()) {
        self.init(state: .newGame(difficulty: difficulty, seed: seed), undoPolicy: undoPolicy, scoring: scoring)
    }

    /// Start from an arbitrary position (tests, restored saves).
    public init(state: GameState, undoPolicy: UndoPolicy = .unlimited, scoring: ScoringRules = ScoringRules()) {
        self.state = state
        self.undoPolicy = undoPolicy
        self.scoring = scoring
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var undoDepth: Int { undoStack.count }
    public var canRedo: Bool { !redoStack.isEmpty && !state.isWon }
    /// What Redo would do next.
    public var nextRedo: Action? { state.isWon ? nil : redoStack.last }

    public func canPerform(_ action: Action) -> Bool {
        guard !state.isWon else { return false }
        switch action {
        case let .move(from, index, to):
            return state.columns.indices.contains(from) && state.canMove(from: from, index: index, to: to)
        case .deal:
            return state.canDeal
        }
    }

    /// Performs a new action. This clears the redo history.
    @discardableResult
    public mutating func perform(_ action: Action) throws -> ActionOutcome {
        let outcome = try apply(action)
        redoStack.removeAll()
        return outcome
    }

    /// Performs the most recently undone action again. It counts as a move like any other (penalty
    /// and Moves counter), since undo's own penalty is never refunded.
    @discardableResult
    public mutating func redo() throws -> ActionOutcome {
        guard let action = nextRedo else { throw state.isWon ? GameError.gameOver : GameError.nothingToRedo }
        let outcome = try apply(action)
        redoStack.removeLast()
        return outcome
    }

    private mutating func apply(_ action: Action) throws -> ActionOutcome {
        guard !state.isWon else { throw GameError.gameOver }
        let before = state
        var outcome = ActionOutcome()
        let penalty: Int

        switch action {
        case let .move(from, index, to):
            guard canPerform(action) else { throw GameError.illegalMove }
            let run = state.columns[from][index...]
            state.columns[to].append(contentsOf: run)
            state.columns[from].removeSubrange(index...)
            if let id = flipTop(of: from) { outcome.revealedCardIDs.append(id) }
            penalty = scoring.movePenalty
            removeCompletedRuns(in: [to], outcome: &outcome)

        case .deal:
            if state.stock.isEmpty { throw GameError.stockEmpty }
            guard state.canDeal else { throw GameError.cannotDealWithEmptyColumn }
            for col in 0..<GameState.columnCount {
                guard var card = state.stock.popLast() else { break }
                card.isFaceUp = true
                state.columns[col].append(card)
                outcome.dealtCardIDs.append(card.id)
            }
            penalty = scoring.dealPenalty
            removeCompletedRuns(in: Array(0..<GameState.columnCount), outcome: &outcome)
        }

        state.score -= penalty
        state.moves += 1
        outcome.didWin = state.isWon

        let clearsHistory = undoPolicy == .xpClassic && (action == .deal || !outcome.completedRuns.isEmpty)
        if clearsHistory {
            undoStack.removeAll()
        } else {
            undoStack.append(UndoEntry(before: before, penaltyCharged: penalty, action: action))
        }
        return outcome
    }

    /// Restores the previous position. The undone action's penalty stays, any suit bonus it earned
    /// is lost, and the undo itself costs `undoPenalty`. The move counter keeps counting up.
    public mutating func undo() throws {
        guard let entry = undoStack.popLast() else { throw GameError.nothingToUndo }
        if let action = entry.action {
            redoStack.append(action)
        } else {
            redoStack.removeAll()
        }
        let score = entry.before.score - entry.penaltyCharged - scoring.undoPenalty
        let moves = state.moves + 1
        state = entry.before
        state.score = score
        state.moves = moves
    }

    // MARK: - Helpers

    private mutating func flipTop(of column: Int) -> Int? {
        guard let last = state.columns[column].indices.last, !state.columns[column][last].isFaceUp else { return nil }
        state.columns[column][last].isFaceUp = true
        return state.columns[column][last].id
    }

    private mutating func removeCompletedRuns(in columns: [Int], outcome: inout ActionOutcome) {
        for col in columns {
            guard let suit = state.completedRun(in: col) else { continue }
            let cards = Array(state.columns[col].suffix(13))
            state.columns[col].removeLast(13)
            outcome.completedRuns.append(CompletedRun(column: col, suit: suit, cards: cards,
                                                      foundationSlot: state.completed.count))
            state.completed.append(suit)
            state.score += scoring.completedSuitBonus
            if let id = flipTop(of: col) { outcome.revealedCardIDs.append(id) }
        }
    }
}
