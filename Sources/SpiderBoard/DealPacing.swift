import SpiderCore

/// Timing of the two deal animations, XP style: cards leave the stock one after another and
/// each one flies (ease-out) to its column, so you can follow every card landing. All deal
/// timing lives here; `DealPacingTests` pins the totals.
public enum DealPacing {
    public enum Kind: Hashable, Sendable {
        /// The 54 cards of a new game (or a restart).
        case initial
        /// 10 cards from the stock, one per column.
        case stock
    }

    /// Flight time of one card, stock to column (ease-out).
    public static let flightDuration: Double = 0.24
    /// Time between two cards leaving the stock.
    public static let stockStagger: Double = 0.08
    /// The initial deal staggers a little tighter, so 54 cards take about 3 s, not 4.5 s.
    public static let initialStagger: Double = 0.05
    /// Pause before a new game's first card leaves, so the empty board is seen first.
    public static let initialLeadIn: Double = 0.15

    public static func stagger(_ kind: Kind) -> Double {
        switch kind {
        case .initial: return initialStagger
        case .stock: return stockStagger
        }
    }

    public static func leadIn(_ kind: Kind) -> Double {
        kind == .initial ? initialLeadIn : 0
    }

    /// When card `index` (0-based, in deal order) leaves the stock, from the start of the deal.
    public static func releaseTime(_ kind: Kind, index: Int) -> Double {
        leadIn(kind) + stagger(kind) * Double(max(0, index))
    }

    /// From the start of the deal until the last of `cards` has landed.
    public static func totalDuration(_ kind: Kind, cards: Int) -> Double {
        guard cards > 0 else { return 0 }
        return releaseTime(kind, index: cards - 1) + flightDuration
    }

    /// Whether card `index` plays the deal sound. Every card of a stock deal clicks; the initial
    /// deal clicks once per row of ten (a click every 50 ms would be one long buzz).
    public static func playsSound(_ kind: Kind, index: Int) -> Bool {
        switch kind {
        case .stock: return true
        case .initial: return index.isMultiple(of: GameState.columnCount)
        }
    }

    /// One card of a deal: when it leaves the stock, when it lands, and whether it clicks.
    public struct CardStep: Hashable, Sendable {
        public let id: Int
        public let release: Double
        public let landing: Double
        public let sound: Bool
    }

    /// A timed step for every card of a deal, in deal order, `delay` seconds after now. A stock
    /// card the deal completed into a run does not wait on the stock (it flies to the foundation),
    /// but it keeps its step, so it still clicks at its place in the rhythm.
    public static func steps(_ kind: Kind, ids: [Int], delay: Double = 0) -> [CardStep] {
        ids.enumerated().map { i, id in
            let release = delay + releaseTime(kind, index: i)
            return CardStep(
                id: id, release: release, landing: release + flightDuration, sound: playsSound(kind, index: i))
        }
    }

    /// Order the initial deal hands out cards: row by row, left to right, like dealing by hand
    /// (columns 1–4 get the sixth row). Ids of `columns`, each column bottom card first.
    public static func initialDealOrder(_ columns: [[Card]]) -> [Int] {
        let rows: Int = columns.map(\.count).max() ?? 0
        var order: [Int] = []
        for row in 0..<rows {
            for column in columns where row < column.count {
                order.append(column[row].id)
            }
        }
        return order
    }
}
