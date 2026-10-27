/// Snapshot of everything on the table. A plain value type, so undo is "keep the old value".
public struct GameState: Codable, Sendable, Hashable {
    public static let columnCount = 10
    public static let initialScore = 500
    public static let suitsToWin = 8

    public var difficulty: Difficulty
    public var seed: UInt64
    /// Ten tableau columns; index 0 is the bottom (back) card, `last` is the exposed top card.
    public var columns: [[Card]]
    /// Undealt cards, dealt from the end. Always a multiple of 10 at rest (5 deals of 10).
    public var stock: [Card]
    /// Suit of each completed K..A run, in completion order (drawn bottom-left in the UI).
    public var completed: [Suit]
    public var score: Int
    /// XP's "Moves" counter: card moves, deals and undos all count.
    public var moves: Int

    public init(difficulty: Difficulty, seed: UInt64, columns: [[Card]], stock: [Card],
                completed: [Suit] = [], score: Int = GameState.initialScore, moves: Int = 0) {
        self.difficulty = difficulty
        self.seed = seed
        self.columns = columns
        self.stock = stock
        self.completed = completed
        self.score = score
        self.moves = moves
    }

    /// Fresh XP layout: columns 0-3 get 6 cards, 4-9 get 5 (54 total), top card face up; 50 in stock.
    public static func newGame(difficulty: Difficulty, seed: UInt64) -> GameState {
        var cards = Deck.shuffled(difficulty, seed: seed)
        var columns = Array(repeating: [Card](), count: columnCount)
        for col in 0..<columnCount {
            let n = col < 4 ? 6 : 5
            columns[col] = Array(cards.prefix(n))
            cards.removeFirst(n)
            columns[col][n - 1].isFaceUp = true
        }
        return GameState(difficulty: difficulty, seed: seed, columns: columns, stock: cards)
    }

    public var isWon: Bool { completed.count == GameState.suitsToWin }

    /// Cards in the stock before the first deal (5 deals of 10).
    public static let fullStockCount = 50

    /// Remaining deals shown as stacked backs in the bottom-right corner.
    public var dealsRemaining: Int { stock.count / GameState.columnCount }

    public var tableauCardCount: Int { columns.reduce(0) { $0 + $1.count } }

    /// Index of the first card of the longest same-suit descending face-up run ending at the top,
    /// or nil for an empty column. Any suffix starting at or after this index may be picked up.
    public func movableRunStart(in column: Int) -> Int? {
        let cards = columns[column]
        guard var start = cards.indices.last, cards[start].isFaceUp else { return nil }
        while start > 0, cards[start - 1].isFaceUp, cards[start].continuesRun(on: cards[start - 1]) {
            start -= 1
        }
        return start
    }

    /// True if the cards from `index` to the top of `column` can be picked up together.
    public func canPickUp(column: Int, from index: Int) -> Bool {
        guard columns.indices.contains(column), let start = movableRunStart(in: column) else { return false }
        return index >= start && index < columns[column].count
    }

    /// A run may land on an empty column or on a card exactly one rank higher, any suit.
    public func canMove(from source: Int, index: Int, to destination: Int) -> Bool {
        guard source != destination, columns.indices.contains(destination),
              canPickUp(column: source, from: index) else { return false }
        guard let target = columns[destination].last else { return true }
        return target.isFaceUp && target.rank.rawValue == columns[source][index].rank.rawValue + 1
    }

    /// XP forbids dealing while a column is empty. Exception: if there are fewer tableau cards than
    /// columns, filling every column is impossible, so the deal is allowed.
    public var canDeal: Bool {
        guard !stock.isEmpty else { return false }
        let hasEmpty = columns.contains { $0.isEmpty }
        return !hasEmpty || tableauCardCount < GameState.columnCount
    }

    /// If the top 13 cards of `column` are a face-up K..A run of one suit, returns that suit.
    public func completedRun(in column: Int) -> Suit? {
        let cards = columns[column]
        guard cards.count >= 13 else { return nil }
        let run = cards.suffix(13)
        guard let first = run.first, first.rank == .king, first.isFaceUp else { return nil }
        var previous = first
        for card in run.dropFirst() {
            guard card.isFaceUp, card.continuesRun(on: previous) else { return nil }
            previous = card
        }
        return first.suit
    }
}
