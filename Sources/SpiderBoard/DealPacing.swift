import SpiderCore

/// Timing of the two deal animations, XP style: cards leave the stock one after another, about
/// ten a second, and each one flies (ease-out) to its column, so you can follow every card being
/// placed. All deal timing lives here; `DealPacingTests` pins the totals.
public enum DealPacing {
    public enum Kind: Hashable, Sendable {
        /// The 54 cards of a new game (or a restart).
        case initial
        /// 10 cards from the stock, one per column.
        case stock
    }

    /// Flight time of one card, stock to column (ease-out).
    public static let flightDuration: Double = 0.3
    /// Time between two cards leaving the stock: 10 cards a second, about 1.2 s for a row.
    public static let stockStagger: Double = 0.1
    /// A new game hands out its 54 cards about 9 a second (about 6.4 s), slow enough to see
    /// every card placed, as in XP.
    public static let initialStagger: Double = 0.11
    /// Pause before a new game's first card leaves, so the empty board is seen first.
    public static let initialLeadIn: Double = 0.3

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

    /// One card of a deal: when it leaves the stock (with the deal click) and when it lands.
    public struct CardStep: Hashable, Sendable {
        public let id: Int
        public let release: Double
        public let landing: Double
    }

    /// A timed step for every card of a deal, in deal order, `delay` seconds after now. Every card
    /// clicks as it leaves. A stock card the deal completed into a run does not wait on the stock
    /// (it flies to the foundation), but it keeps its step, so it still clicks at its place in the
    /// rhythm.
    public static func steps(_ kind: Kind, ids: [Int], delay: Double = 0) -> [CardStep] {
        ids.enumerated().map { i, id in
            let release = delay + releaseTime(kind, index: i)
            return CardStep(id: id, release: release, landing: release + flightDuration)
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
