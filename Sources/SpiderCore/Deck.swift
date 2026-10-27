/// Deterministic SplitMix64 generator, so a seed reproduces a deal on every platform.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in 0..<upperBound without modulo bias (Lemire-free simple rejection).
    mutating func uniform(below upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let bound = UInt64(upperBound)
        let limit = UInt64.max - (UInt64.max % bound)
        while true {
            let value = next()
            if value < limit { return Int(value % bound) }
        }
    }
}

public enum Deck {
    public static let cardCount = 104

    /// Two decks' worth of cards (104) for the difficulty, face down, in canonical order.
    public static func make(_ difficulty: Difficulty) -> [Card] {
        let suits = difficulty.suits
        let copies = cardCount / (suits.count * Rank.allCases.count)
        var cards: [Card] = []
        cards.reserveCapacity(cardCount)
        var id = 0
        for _ in 0..<copies {
            for suit in suits {
                for rank in Rank.allCases {
                    cards.append(Card(id: id, suit: suit, rank: rank))
                    id += 1
                }
            }
        }
        return cards
    }

    /// Fisher–Yates shuffle with our own generator (Swift's `shuffle(using:)` algorithm is not
    /// guaranteed stable across toolchains, so seeds would not be portable).
    public static func shuffled(_ difficulty: Difficulty, seed: UInt64) -> [Card] {
        var cards = make(difficulty)
        var rng = SeededGenerator(seed: seed)
        var i = cards.count - 1
        while i > 0 {
            let j = rng.uniform(below: i + 1)
            cards.swapAt(i, j)
            i -= 1
        }
        return cards
    }
}
