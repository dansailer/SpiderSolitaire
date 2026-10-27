import SpiderCore

/// One card to draw: where, how high in the stack, and whether it is being dragged.
public struct CardPlacement: Hashable, Sendable, Identifiable {
    public let card: Card
    /// Frame including any drag translation.
    public let frame: BoardRect
    public let zIndex: Double
    public let isLifted: Bool
    public var id: Int { card.id }
}

extension BoardLayout {
    /// Every stock and tableau card with its frame. Keyed by stable card id, so when the state
    /// changes inside an animation, SwiftUI moves each card from its old frame to its new one
    /// (stock → column on deal, column → column on move, dragged spot → target or back).
    public func placements(for state: GameState, drag: PointerController.Drag? = nil) -> [CardPlacement] {
        var result: [CardPlacement] = []
        result.reserveCapacity(state.stock.count + state.tableauCardCount)

        let deals = state.dealsRemaining
        for (i, card) in state.stock.enumerated() {
            guard let frame = stockFrame(forStockIndex: i, dealsRemaining: deals) else { continue }
            result.append(CardPlacement(card: card, frame: frame, zIndex: Double(i), isLifted: false))
        }

        for column in state.columns.indices {
            let frames = cardFrames(column: column, cards: state.columns[column])
            for (index, card) in state.columns[column].enumerated() {
                let lifted = drag.map { $0.from == column && index >= $0.index } ?? false
                var frame = frames[index]
                if lifted, let drag { frame = frame.offsetBy(dx: drag.translation.width, dy: drag.translation.height) }
                let z = (lifted ? 1000.0 : 100.0) + Double(index)
                result.append(CardPlacement(card: card, frame: frame, zIndex: z, isLifted: lifted))
            }
        }
        return result
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
