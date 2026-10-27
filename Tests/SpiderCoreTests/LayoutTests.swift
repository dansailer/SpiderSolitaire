import XCTest
@testable import SpiderCore

final class LayoutTests: XCTestCase {
    func testInitialLayoutMatchesXP() {
        let state = GameState.newGame(difficulty: .twoSuits, seed: 99)
        XCTAssertEqual(state.columns.count, 10)
        XCTAssertEqual(state.columns.map(\.count), [6, 6, 6, 6, 5, 5, 5, 5, 5, 5])
        XCTAssertEqual(state.tableauCardCount, 54)
        XCTAssertEqual(state.stock.count, 50)
        XCTAssertEqual(state.dealsRemaining, 5)
        XCTAssertEqual(state.score, 500)
        XCTAssertEqual(state.moves, 0)
        XCTAssertTrue(state.completed.isEmpty)
        for column in state.columns {
            XCTAssertTrue(column.last!.isFaceUp)
            XCTAssertTrue(column.dropLast().allSatisfy { !$0.isFaceUp })
        }
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        let all = state.columns.flatMap { $0 } + state.stock
        XCTAssertEqual(Set(all.map(\.id)).count, 104)
    }

    func testSameSeedSameGame() {
        XCTAssertEqual(GameState.newGame(difficulty: .fourSuits, seed: 5),
                       GameState.newGame(difficulty: .fourSuits, seed: 5))
    }

    func testOneSuitGameIsAllSpades() {
        let state = GameState.newGame(difficulty: .oneSuit, seed: 1)
        XCTAssertTrue((state.columns.flatMap { $0 } + state.stock).allSatisfy { $0.suit == .spades })
    }
}
