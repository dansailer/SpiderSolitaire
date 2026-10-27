@testable import SpiderCore

/// Builds hand-made positions. Ids start high so they never collide with a real deck.
struct Table {
    private var nextID = 1000

    mutating func c(_ rank: Rank, _ suit: Suit = .spades, up: Bool = true) -> Card {
        nextID += 1
        return Card(id: nextID, suit: suit, rank: rank, isFaceUp: up)
    }

    /// Face-up same-suit run from `high` down to `low`.
    mutating func run(_ high: Rank, _ low: Rank, _ suit: Suit = .spades) -> [Card] {
        stride(from: high.rawValue, through: low.rawValue, by: -1).map { c(Rank(rawValue: $0)!, suit) }
    }

    /// State with the given columns (padded to 10 with single face-up kings unless `pad` is false).
    mutating func state(
        _ columns: [[Card]], stock: [Card] = [], completed: [Suit] = [],
        pad: Bool = true
    ) -> GameState {
        var cols = columns
        while cols.count < GameState.columnCount { cols.append(pad ? [c(.king, .clubs)] : []) }
        return GameState(difficulty: .fourSuits, seed: 0, columns: cols, stock: stock, completed: completed)
    }

    mutating func stock(_ count: Int, _ rank: Rank = .five, _ suit: Suit = .diamonds) -> [Card] {
        (0..<count).map { _ in c(rank, suit, up: false) }
    }
}
