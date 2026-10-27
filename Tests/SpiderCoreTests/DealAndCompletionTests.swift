import XCTest
@testable import SpiderCore

final class DealAndCompletionTests: XCTestCase {
    func testDealPutsOneFaceUpCardOnEachColumnAndIsFree() throws {
        var game = SpiderGame(difficulty: .fourSuits, seed: 3)
        let before = game.state
        let expected = Array(before.stock.suffix(10).reversed()).map(\.id)
        let outcome = try game.perform(.deal)
        XCTAssertEqual(game.state.stock.count, 40)
        XCTAssertEqual(game.state.dealsRemaining, 4)
        XCTAssertEqual(game.state.columns.map { $0.last!.id }, expected)
        XCTAssertEqual(outcome.dealtCardIDs, expected)
        XCTAssertTrue(game.state.columns.allSatisfy { $0.last!.isFaceUp })
        XCTAssertEqual(game.state.columns.map(\.count), before.columns.map { $0.count + 1 })
        XCTAssertEqual(game.state.score, 500)
        XCTAssertEqual(game.state.moves, 1)
    }

    func testFiveDealsThenStockEmpty() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 11)
        for _ in 0..<5 where game.state.canDeal { try game.perform(.deal) }
        XCTAssertEqual(game.state.stock.count, 0)
        XCTAssertFalse(game.state.canDeal)
        XCTAssertThrowsError(try game.perform(.deal)) { XCTAssertEqual($0 as? GameError, .stockEmpty) }
    }

    func testCannotDealWithAnEmptyColumn() {
        var t = Table()
        // 9 kings + a 2-card column = 11 cards, so the "too few cards" exception does not apply.
        var game = SpiderGame(state: t.state([[], [t.c(.three, up: false), t.c(.king)]], stock: t.stock(10)))
        XCTAssertFalse(game.state.canDeal)
        XCTAssertThrowsError(try game.perform(.deal)) {
            XCTAssertEqual($0 as? GameError, .cannotDealWithEmptyColumn)
        }
    }

    func testDealAllowedWhenTooFewCardsToFillColumns() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([[t.c(.four)], [t.c(.two)]], stock: t.stock(10), pad: false))
        XCTAssertTrue(game.state.canDeal)
        try game.perform(.deal)
        XCTAssertEqual(game.state.columns.map(\.count), [2, 2, 1, 1, 1, 1, 1, 1, 1, 1])
    }

    func testMoveCompletingKingToAceRemovesRunAndScores100() throws {
        var t = Table()
        let hidden = t.c(.five, .clubs, up: false)
        var game = SpiderGame(state: t.state([
            [hidden] + t.run(.king, .two, .hearts),
            [t.c(.ace, .hearts)],
        ]))
        let outcome = try game.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertEqual(outcome.completedRuns.map(\.column), [0])
        XCTAssertEqual(outcome.completedRuns.map(\.suit), [.hearts])
        XCTAssertEqual(outcome.completedRuns[0].cards.map(\.rank), Rank.allCases.reversed())
        XCTAssertTrue(outcome.completedRuns[0].cards.allSatisfy { $0.suit == .hearts && $0.isFaceUp })
        XCTAssertEqual(outcome.completedRuns[0].foundationSlot, 0)
        XCTAssertTrue(outcome.dealtCardIDs.isEmpty)
        XCTAssertEqual(outcome.revealedCardIDs, [hidden.id])
        XCTAssertEqual(game.state.completed, [.hearts])
        XCTAssertEqual(game.state.columns[0].map(\.id), [hidden.id])
        XCTAssertTrue(game.state.columns[0][0].isFaceUp)
        XCTAssertTrue(game.state.columns[1].isEmpty)
        XCTAssertEqual(game.state.score, 500 - 1 + 100)
    }

    func testMixedSuitKingToAceIsNotCompleted() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([t.run(.king, .two, .hearts), [t.c(.ace, .spades)]]))
        let outcome = try game.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertTrue(outcome.completedRuns.isEmpty)
        XCTAssertEqual(game.state.columns[0].count, 13)
        XCTAssertNil(game.state.completedRun(in: 0))
    }

    func testDealCanCompleteARun() throws {
        var t = Table()
        var stock = t.stock(10, .five, .clubs)
        stock[stock.count - 1] = t.c(.ace, .spades, up: false) // popped first -> column 0
        var game = SpiderGame(state: t.state([t.run(.king, .two)], stock: stock))
        let outcome = try game.perform(.deal)
        XCTAssertEqual(outcome.completedRuns.map(\.column), [0])
        XCTAssertEqual(outcome.completedRuns[0].cards.last?.id, stock.last?.id, "the dealt ace is in the run")
        XCTAssertEqual(outcome.dealtCardIDs, stock.reversed().map(\.id))
        XCTAssertEqual(game.state.columns[0].count, 0)
        XCTAssertEqual(game.state.score, 600)
    }

    func testEighthSuitWinsAndEndsGame() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([t.run(.king, .two), [t.c(.ace)]],
                                             completed: Array(repeating: .spades, count: 7), pad: false))
        let outcome = try game.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertEqual(outcome.completedRuns.first?.foundationSlot, 7)
        XCTAssertTrue(outcome.didWin)
        XCTAssertTrue(game.state.isWon)
        XCTAssertEqual(game.state.tableauCardCount, 0)
        XCTAssertFalse(game.canPerform(.deal))
        XCTAssertThrowsError(try game.perform(.deal)) { XCTAssertEqual($0 as? GameError, .gameOver) }
    }
}
