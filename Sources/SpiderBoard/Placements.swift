import SpiderCore

/// One card to draw: where, how high in the stack, and how.
public struct CardPlacement: Hashable, Sendable, Identifiable {
    /// The card as it should be drawn (`isFaceUp` may differ from the game state while a dealt
    /// card is still waiting on the stock).
    public let card: Card
    /// Frame including any drag translation or animation override.
    public let frame: BoardRect
    public let zIndex: Double
    public let isLifted: Bool
    /// Part of the current hint flash (drawn inverted, like XP).
    public let isHighlighted: Bool
    public var id: Int { card.id }

    public init(card: Card, frame: BoardRect, zIndex: Double, isLifted: Bool = false, isHighlighted: Bool = false) {
        self.card = card
        self.frame = frame
        self.zIndex = zIndex
        self.isLifted = isLifted
        self.isHighlighted = isHighlighted
    }
}

extension BoardLayout {
    /// Every stock, tableau and in-flight card with its frame. Keyed by stable card id, so when
    /// the state changes inside an animation, SwiftUI moves each card from its old frame to its
    /// new one (stock to column on deal, column to column on move, dragged spot to target or back).
    ///
    /// - `animations`: dealt cards still held on the stock, and completed-run cards flying to the
    ///   foundation (they are no longer in `state`).
    /// - `highlightedIDs`: cards to draw inverted for the hint flash.
    public func placements(
        for state: GameState, drag: PointerController.Drag? = nil,
        animations: BoardAnimations = BoardAnimations(),
        highlightedIDs: Set<Int> = []
    ) -> [CardPlacement] {
        var result: [CardPlacement] = []
        result.reserveCapacity(state.stock.count + state.tableauCardCount + animations.flying.count)

        let deals = state.dealsRemaining
        for (i, card) in state.stock.enumerated() {
            guard let frame = stockFrame(forStockIndex: i, dealsRemaining: deals) else { continue }
            result.append(
                CardPlacement(
                    card: card, frame: frame, zIndex: Double(i),
                    isHighlighted: highlightedIDs.contains(card.id)))
        }

        let heldFrame: BoardRect? = animations.dealHold.flatMap { stockFrames(dealsRemaining: $0.dealsBefore).last }
        let held: [Int: Int] =
            animations.dealHold.map { hold in
                Dictionary(uniqueKeysWithValues: hold.waitingIDs.enumerated().map { ($0.element, $0.offset) })
            } ?? [:]

        for column in state.columns.indices {
            let frames = cardFrames(column: column, cards: state.columns[column])
            for (index, card) in state.columns[column].enumerated() {
                if let order = held[card.id], let heldFrame {
                    var faceDown = card
                    faceDown.isFaceUp = false
                    // Waiting cards sit on the stock, the next to fly on top.
                    result.append(
                        CardPlacement(card: faceDown, frame: heldFrame, zIndex: 60 + Double(held.count - order)))
                    continue
                }
                let lifted = drag.map { $0.from == column && index >= $0.index } ?? false
                var frame = frames[index]
                if lifted, let drag { frame = frame.offsetBy(dx: drag.translation.width, dy: drag.translation.height) }
                let z = (lifted ? 1000.0 : 100.0) + Double(index)
                result.append(
                    CardPlacement(
                        card: card, frame: frame, zIndex: z, isLifted: lifted,
                        isHighlighted: highlightedIDs.contains(card.id)))
            }
        }

        for flight in animations.flying {
            result.append(
                CardPlacement(card: flight.card, frame: frame(of: flight), zIndex: 3000 + Double(flight.runIndex)))
        }
        return result
    }

    /// Where a flying card is: on top of its old column until it takes off, then on its
    /// foundation slot.
    public func frame(of flight: FlyingCard) -> BoardRect {
        if flight.arrived {
            return foundationFrames(count: flight.foundationSlot + 1)[flight.foundationSlot]
        }
        let frames = cardFrames(column: flight.column, cards: flight.columnBelow + flight.run)
        return frames[flight.columnBelow.count + flight.runIndex]
    }

    /// Completed-suit kings in the bottom-left, minus slots whose run is still in the air.
    public func foundationPlacements(
        for state: GameState,
        animations: BoardAnimations = BoardAnimations()
    ) -> [CardPlacement] {
        let pending = Set(animations.flying.map(\.foundationSlot))
        let frames = foundationFrames(count: state.completed.count)
        return state.completed.enumerated().compactMap { slot, suit in
            guard !pending.contains(slot) else { return nil }
            // Negative ids never collide with real cards (0...103).
            let king = Card(id: -1 - slot, suit: suit, rank: .king, isFaceUp: true)
            return CardPlacement(card: king, frame: frames[slot], zIndex: 50 + Double(slot))
        }
    }
}

/// Pip positions for number cards, normalised to the pip area (0...1 in both axes).
/// `inverted` pips (lower half) are drawn upside down, as on real cards.
public struct Pip: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public var inverted: Bool { y > 0.5 }
}

public enum CardFace {
    /// Pip area inside the card, as fractions of card width/height.
    public static let pipArea = (minX: 0.27, maxX: 0.73, minY: 0.17, maxY: 0.83)

    /// Classic pip layouts for A–10; empty for court cards (drawn as framed letters).
    public static func pips(for rank: Rank) -> [Pip] {
        let l = 0.0, m = 0.5, r = 1.0
        let corners = [Pip(x: l, y: 0), Pip(x: r, y: 0), Pip(x: l, y: 1), Pip(x: r, y: 1)]
        let six = corners + [Pip(x: l, y: 0.5), Pip(x: r, y: 0.5)]
        let nineGrid = [0.0, 1.0 / 3, 2.0 / 3, 1.0].flatMap { y in [Pip(x: l, y: y), Pip(x: r, y: y)] }
        switch rank {
        case .ace: return [Pip(x: m, y: 0.5)]
        case .two: return [Pip(x: m, y: 0), Pip(x: m, y: 1)]
        case .three: return [Pip(x: m, y: 0), Pip(x: m, y: 0.5), Pip(x: m, y: 1)]
        case .four: return corners
        case .five: return corners + [Pip(x: m, y: 0.5)]
        case .six: return six
        case .seven: return six + [Pip(x: m, y: 0.25)]
        case .eight: return six + [Pip(x: m, y: 0.25), Pip(x: m, y: 0.75)]
        case .nine: return nineGrid + [Pip(x: m, y: 0.5)]
        case .ten: return nineGrid + [Pip(x: m, y: 1.0 / 6), Pip(x: m, y: 5.0 / 6)]
        case .jack, .queen, .king: return []
        }
    }

    public static func isCourt(_ rank: Rank) -> Bool { rank == .jack || rank == .queen || rank == .king }
}
