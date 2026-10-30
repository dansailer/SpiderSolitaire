import SpiderCore

/// A card of a completed run on its way to the foundation. It has already left `GameState`.
public struct FlyingCard: Hashable, Sendable {
    public let card: Card
    public let column: Int
    /// 0 = King (bottom of the run) ... 12 = Ace (top).
    public let runIndex: Int
    public let foundationSlot: Int
    /// The column as it was just after removal, so the source frame is where the card was drawn.
    public let columnBelow: [Card]
    public let run: [Card]
    public var arrived: Bool
}

/// Cards a deal put on the columns that are still drawn on the stock, waiting for their turn.
public struct DealHold: Hashable, Sendable {
    /// Waiting ids in release order (column 1 first).
    public private(set) var waitingIDs: [Int]
    /// Deals left before this deal, so the cards wait on the pile they came from.
    public let dealsBefore: Int

    public init(waitingIDs: [Int], dealsBefore: Int) {
        self.waitingIDs = waitingIDs
        self.dealsBefore = dealsBefore
    }

    mutating func release(_ id: Int) { waitingIDs.removeAll { $0 == id } }
}

/// Transient animation state on top of `GameState`. Pure data: the app schedules the steps
/// (with delays) and each step is a small mutation done inside `withAnimation`.
public struct BoardAnimations: Hashable, Sendable {
    public static let flyStagger: Double = 0.04
    public static let flyDuration: Double = 0.28

    public private(set) var dealHold: DealHold?
    /// Dealt cards that have left the stock and are still flying to their column, in release
    /// order. They fly face down; a card dealt face up turns over when it lands (`landDealtCard`).
    public private(set) var landingDealtIDs: [Int] = []
    public private(set) var flying: [FlyingCard] = []
    /// Cards gliding to another column (a move, undo or redo) or back to their own (a drop that
    /// was not allowed). They are drawn above every column until `endMoves`, so they never pass
    /// behind one on the way.
    public private(set) var movingIDs: Set<Int> = []

    public init() {}

    /// No deal or completed-run flight is running. Gliding moves (`movingIDs`) do not count: they
    /// only raise cards for a moment and announce nothing.
    public var isIdle: Bool { dealHold == nil && landingDealtIDs.isEmpty && flying.isEmpty }

    public mutating func beginMoves(_ ids: Set<Int>) { movingIDs.formUnion(ids) }

    /// The glide is over: the cards go back to their column's drawing order.
    public mutating func endMoves() { movingIDs.removeAll() }

    /// Cards that `after` has in another column than `before` did, or that went between the stock
    /// and a column (undoing a deal). Cards that left the tableau are not included.
    public static func movedCardIDs(from before: GameState, to after: GameState) -> Set<Int> {
        func places(_ state: GameState) -> [Int: Int] {
            var place: [Int: Int] = [:]
            for card in state.stock { place[card.id] = -1 }
            for (column, cards) in state.columns.enumerated() {
                for card in cards { place[card.id] = column }
            }
            return place
        }
        let old = places(before)
        return Set(places(after).compactMap { id, place in old[id] == place ? nil : id })
    }

    /// Start a deal animation: `outcome.dealtCardIDs` wait on the stock, minus cards that the deal
    /// completed into a run (those fly to the foundation instead).
    public mutating func beginDeal(_ outcome: ActionOutcome, dealsBefore: Int) {
        let flown = Set(outcome.completedRuns.flatMap { $0.cards.map(\.id) })
        let waiting = outcome.dealtCardIDs.filter { !flown.contains($0) }
        dealHold = waiting.isEmpty ? nil : DealHold(waitingIDs: waiting, dealsBefore: dealsBefore)
        landingDealtIDs = []
    }

    /// Start the deal of a new game: every tableau card waits on the stock, then they are handed
    /// out in `DealPacing.initialDealOrder` (row by row). They wait on the stock's top pile.
    public mutating func beginInitialDeal(_ state: GameState) {
        let order = DealPacing.initialDealOrder(state.columns)
        dealHold = order.isEmpty ? nil : DealHold(waitingIDs: order, dealsBefore: max(1, state.dealsRemaining))
        landingDealtIDs = []
    }

    /// True from the start of a deal until its last card has landed: while cards still wait on
    /// the stock and while released ones are still in the air.
    public var isDealing: Bool { dealHold != nil || !landingDealtIDs.isEmpty }

    /// Release one dealt card to its column; it is in the air until `landDealtCard`. Returns
    /// false if it was not waiting.
    @discardableResult
    public mutating func releaseDealtCard(_ id: Int) -> Bool {
        guard var hold = dealHold, hold.waitingIDs.contains(id) else { return false }
        hold.release(id)
        dealHold = hold.waitingIDs.isEmpty ? nil : hold
        landingDealtIDs.append(id)
        return true
    }

    /// A released dealt card reached its column. Returns false if it was not in the air.
    @discardableResult
    public mutating func landDealtCard(_ id: Int) -> Bool {
        guard let i = landingDealtIDs.firstIndex(of: id) else { return false }
        landingDealtIDs.remove(at: i)
        return true
    }

    /// Put the cards of each completed run in the air, still at their column positions.
    /// `columns` is the tableau right after the action (the runs already removed).
    public mutating func beginFlights(_ runs: [CompletedRun], columns: [[Card]]) {
        for run in runs {
            let below = columns.indices.contains(run.column) ? columns[run.column] : []
            for (i, card) in run.cards.enumerated() {
                flying.append(
                    FlyingCard(
                        card: card, column: run.column, runIndex: i,
                        foundationSlot: run.foundationSlot, columnBelow: below,
                        run: run.cards, arrived: false))
            }
        }
    }

    /// Order cards take off for one slot: top of the run (Ace) first, as you would lift them.
    public func takeOffOrder(slot: Int) -> [Int] {
        flying.filter { $0.foundationSlot == slot }.sorted { $0.runIndex > $1.runIndex }.map(\.card.id)
    }

    public var flyingSlots: [Int] {
        var seen: [Int] = []
        for f in flying where !seen.contains(f.foundationSlot) { seen.append(f.foundationSlot) }
        return seen
    }

    public mutating func land(_ id: Int) {
        if let i = flying.firstIndex(where: { $0.card.id == id }) { flying[i].arrived = true }
    }

    /// Drop the in-flight cards of a slot once all have landed; the foundation king takes over.
    public mutating func finishSlot(_ slot: Int) {
        flying.removeAll { $0.foundationSlot == slot }
    }
}
