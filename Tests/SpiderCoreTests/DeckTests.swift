import XCTest

@testable import SpiderCore

final class DeckTests: XCTestCase {
    func testEveryDifficultyHas104CardsAndEightFullSuits() {
        for difficulty in Difficulty.allCases {
            let cards = Deck.make(difficulty)
            XCTAssertEqual(cards.count, 104)
            XCTAssertEqual(Set(cards.map(\.id)).count, 104, "ids unique")
            XCTAssertEqual(Set(cards.map(\.suit)), Set(difficulty.suits))
            for suit in difficulty.suits {
                for rank in Rank.allCases {
                    let n = cards.filter { $0.suit == suit && $0.rank == rank }.count
                    XCTAssertEqual(n, 8 / difficulty.suits.count, "\(difficulty) \(suit) \(rank)")
                }
            }
            XCTAssertTrue(cards.allSatisfy { !$0.isFaceUp })
        }
    }

    func testShuffleIsDeterministicPerSeed() {
        let a = Deck.shuffled(.fourSuits, seed: 42)
        let b = Deck.shuffled(.fourSuits, seed: 42)
        let c = Deck.shuffled(.fourSuits, seed: 43)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, Deck.make(.fourSuits))
        XCTAssertEqual(Set(a.map(\.id)), Set(Deck.make(.fourSuits).map(\.id)), "a permutation")
    }

    func testShuffleIsStableAcrossToolchains() {
        // Golden values: if this fails, saved seeds no longer reproduce the same deals.
        var rng = SeededGenerator(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(Deck.shuffled(.fourSuits, seed: 2026).prefix(8).map(\.id), [5, 78, 18, 21, 19, 46, 92, 83])
    }

    func testUniformStaysInRange() {
        var rng = SeededGenerator(seed: 7)
        for bound in 1...60 {
            for _ in 0..<50 { XCTAssertTrue((0..<bound).contains(rng.uniform(below: bound))) }
        }
    }
}
