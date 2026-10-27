/// XP's three levels: Easy (1 suit), Medium (2 suits), Difficult (4 suits).
public enum Difficulty: Int, CaseIterable, Codable, Sendable, Hashable {
    case oneSuit = 1
    case twoSuits = 2
    case fourSuits = 4

    /// Suits used to build the 104-card shoe. 104 / suits.count / 13 copies of each suit.
    public var suits: [Suit] {
        switch self {
        case .oneSuit: return [.spades]
        case .twoSuits: return [.spades, .hearts]
        case .fourSuits: return Suit.allCases
        }
    }

    public var displayName: String {
        switch self {
        case .oneSuit: return "Easy: One Suit"
        case .twoSuits: return "Medium: Two Suits"
        case .fourSuits: return "Difficult: Four Suits"
        }
    }
}
