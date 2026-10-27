/// The four French suits. Order matters only for deterministic deck construction.
public enum Suit: Int, CaseIterable, Codable, Sendable, Hashable {
    case spades, hearts, diamonds, clubs

    public var isRed: Bool { self == .hearts || self == .diamonds }

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }
}

/// Card rank, Ace (1) through King (13).
public enum Rank: Int, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case ace = 1
    case two, three, four, five, six, seven, eight, nine, ten, jack, queen, king

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .ace: return "A"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        default: return String(rawValue)
        }
    }
}

/// A single card. `id` is unique within one 104-card game so the UI can track identity across moves.
public struct Card: Codable, Sendable, Hashable, Identifiable, CustomStringConvertible {
    public let id: Int
    public let suit: Suit
    public let rank: Rank
    public var isFaceUp: Bool

    public init(id: Int, suit: Suit, rank: Rank, isFaceUp: Bool = false) {
        self.id = id
        self.suit = suit
        self.rank = rank
        self.isFaceUp = isFaceUp
    }

    /// True if `self` may sit directly on `other` inside a movable run (same suit, one rank lower).
    public func continuesRun(on other: Card) -> Bool {
        suit == other.suit && rank.rawValue + 1 == other.rank.rawValue
    }

    public var description: String { (isFaceUp ? "" : "#") + rank.label + suit.symbol }
}
