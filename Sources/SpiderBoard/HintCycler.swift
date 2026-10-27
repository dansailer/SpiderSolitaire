import SpiderCore

/// What one press of M (or a click on the score box) should show.
public enum HintStep: Hashable, Sendable {
    case move(Hint)
    /// No card move to suggest, but a deal is possible: flash the stock.
    case deal
    /// Nothing at all: "There are no more moves."
    case noMoves
}

/// Cycles through `GameState.hints()`, wrapping around; restarts when the position changes.
public struct HintCycler: Hashable, Sendable {
    private var position: GameState?
    private var hints: [Hint] = []
    private var nextIndex = 0

    public init() {}

    public mutating func next(for state: GameState) -> HintStep {
        if position != state {
            position = state
            hints = state.isWon ? [] : state.hints()
            nextIndex = 0
        }
        guard !hints.isEmpty else { return state.canDeal ? .deal : .noMoves }
        let hint = hints[nextIndex]
        nextIndex = (nextIndex + 1) % hints.count
        return .move(hint)
    }

    public mutating func reset() {
        position = nil
        hints = []
        nextIndex = 0
    }
}

/// The two-beat XP hint flash: first the run to move, then where it goes.
public enum HintHighlight: Hashable, Sendable {
    case source(column: Int, index: Int)
    case target(column: Int)
    case stock

    public static let beat: Double = 0.55

    /// The flash sequence for a step (empty for `.noMoves`).
    public static func sequence(for step: HintStep) -> [HintHighlight] {
        switch step {
        case .move(let hint): return [.source(column: hint.from, index: hint.index), .target(column: hint.to)]
        case .deal: return [.stock]
        case .noMoves: return []
        }
    }

    /// Card ids drawn inverted for this highlight.
    public func cardIDs(in state: GameState) -> Set<Int> {
        switch self {
        case let .source(column, index):
            guard state.columns.indices.contains(column), index < state.columns[column].count else { return [] }
            return Set(state.columns[column][index...].map(\.id))
        case let .target(column):
            guard state.columns.indices.contains(column), let top = state.columns[column].last else { return [] }
            return [top.id]
        case .stock:
            return Set(state.stock.suffix(GameState.columnCount).map(\.id))
        }
    }

    /// Empty column whose slot outline should light up (target is an empty column).
    public func highlightedSlot(in state: GameState) -> Int? {
        if case let .target(column) = self, state.columns.indices.contains(column), state.columns[column].isEmpty {
            return column
        }
        return nil
    }
}
