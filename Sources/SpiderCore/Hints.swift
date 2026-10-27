/// One suggested move, shown XP-style by flashing the source run then the destination.
public struct Hint: Sendable, Hashable, Codable {
    public enum Kind: Int, Sendable, Hashable, Codable, Comparable {
        /// Onto a card of the same suit: builds a movable run. Shown first.
        case sameSuit = 0
        /// Onto a card of another suit.
        case otherSuit = 1
        /// Into an empty column.
        case emptyColumn = 2

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let from: Int
    public let index: Int
    public let to: Int
    public let kind: Kind

    public var action: Action { .move(from: from, index: index, to: to) }
}

extension GameState {
    /// Useful moves in XP's display order (same suit, then other suit, then empty column; ties by
    /// source then destination column). Like XP, it skips moves that only shuffle a run from one
    /// valid parent to another, so it is a subset of all legal moves. Empty when the player should
    /// deal (or is stuck).
    public func hints() -> [Hint] {
        var result: [Hint] = []
        let emptyColumns = columns.indices.filter { columns[$0].isEmpty }

        for from in columns.indices {
            guard let start = movableRunStart(in: from) else { continue }
            let cards = columns[from]

            for index in start..<cards.count {
                let card = cards[index]
                let parent: Card? = index > 0 && cards[index - 1].isFaceUp ? cards[index - 1] : nil
                let sitsOnSameSuitParent = parent.map { card.continuesRun(on: $0) } ?? false
                let sitsOnAnyParent = parent.map { $0.rank.rawValue == card.rank.rawValue + 1 } ?? false

                for to in columns.indices where to != from {
                    guard let target = columns[to].last, target.isFaceUp,
                          target.rank.rawValue == card.rank.rawValue + 1 else { continue }
                    if target.suit == card.suit {
                        if !sitsOnSameSuitParent { result.append(Hint(from: from, index: index, to: to, kind: .sameSuit)) }
                    } else if !sitsOnAnyParent {
                        result.append(Hint(from: from, index: index, to: to, kind: .otherSuit))
                    }
                }
            }

            // Whole movable run to an empty column, unless it already fills its own column.
            if start > 0, let to = emptyColumns.first {
                result.append(Hint(from: from, index: start, to: to, kind: .emptyColumn))
            }
        }

        return result.enumerated().sorted { a, b in
            a.element.kind != b.element.kind ? a.element.kind < b.element.kind : a.offset < b.offset
        }.map(\.element)
    }

    /// Any legal card move at all (not filtered like `hints()`).
    public var hasLegalMove: Bool {
        for from in columns.indices {
            guard let start = movableRunStart(in: from) else { continue }
            for index in start..<columns[from].count {
                for to in columns.indices where canMove(from: from, index: index, to: to) {
                    if !(columns[to].isEmpty && index == 0) { return true }
                }
            }
        }
        return false
    }
}

extension GameState {
    /// Where a double-click on the card at `index` in `column` should send its run, or nil.
    /// Preference (same as the hint order): a same-suit card one higher, then any card one higher,
    /// then an empty column (only when the run does not already fill its own column).
    /// Ties go to the nearest column to the right, wrapping around, like reading order from the source.
    public func bestDestination(from column: Int, index: Int) -> Int? {
        guard canPickUp(column: column, from: index) else { return nil }
        let card = columns[column][index]
        let order = (1..<GameState.columnCount).map { (column + $0) % GameState.columnCount }
        let legal = order.filter { canMove(from: column, index: index, to: $0) }

        if let to = legal.first(where: { columns[$0].last?.suit == card.suit }) { return to }
        if let to = legal.first(where: { !columns[$0].isEmpty }) { return to }
        if index > 0, let to = legal.first(where: { columns[$0].isEmpty }) { return to }
        return nil
    }
}
