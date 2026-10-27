import XCTest
@testable import SpiderCore

final class MoveRuleTests: XCTestCase {
    func testMovableRunStopsAtSuitBreakRankBreakAndFaceDown() {
        var t = Table()
        let state = t.state([
            [t.c(.nine, up: false), t.c(.eight), t.c(.seven), t.c(.six)],          // whole face-up run
            [t.c(.nine), t.c(.eight, .hearts), t.c(.seven, .hearts)],               // suit break
            [t.c(.nine), t.c(.seven), t.c(.six)],                                    // rank gap
            [t.c(.six, up: false), t.c(.five, up: false)],                           // top face down
            [],
        ])
        XCTAssertEqual(state.movableRunStart(in: 0), 1)
        XCTAssertEqual(state.movableRunStart(in: 1), 1)
        XCTAssertEqual(state.movableRunStart(in: 2), 1)
        XCTAssertNil(state.movableRunStart(in: 3))
        XCTAssertNil(state.movableRunStart(in: 4))
        XCTAssertTrue(state.canPickUp(column: 0, from: 2))
        XCTAssertFalse(state.canPickUp(column: 0, from: 0))
        XCTAssertFalse(state.canPickUp(column: 1, from: 0))
        XCTAssertFalse(state.canPickUp(column: 0, from: 4))
    }

    func testAnyCardMayGoOnOneRankHigherRegardlessOfSuit() {
        var t = Table()
        let state = t.state([
            [t.c(.five, .hearts)],
            [t.c(.six, .clubs)],
            [t.c(.six, .hearts)],
            [t.c(.seven, .hearts)],
            [t.c(.six, .diamonds, up: false)],
            [],
        ])
        XCTAssertTrue(state.canMove(from: 0, index: 0, to: 1), "different suit ok")
        XCTAssertTrue(state.canMove(from: 0, index: 0, to: 2), "same suit ok")
        XCTAssertFalse(state.canMove(from: 0, index: 0, to: 3), "must be exactly one higher")
        XCTAssertFalse(state.canMove(from: 0, index: 0, to: 4), "not onto face-down")
        XCTAssertTrue(state.canMove(from: 0, index: 0, to: 5), "any card to empty column")
        XCTAssertFalse(state.canMove(from: 0, index: 0, to: 0), "not onto itself")
        XCTAssertFalse(state.canMove(from: 0, index: 0, to: 10), "out of range")
        XCTAssertFalse(state.canMove(from: 1, index: 0, to: 0), "not downward in rank")
    }

    func testMovingRunMovesWholeSuffixAndFlipsExposedCard() throws {
        var t = Table()
        let hidden = t.c(.two, .clubs, up: false)
        var game = SpiderGame(state: t.state([
            [hidden] + t.run(.eight, .six, .hearts),
            [t.c(.nine, .spades)],
        ]))
        let outcome = try game.perform(.move(from: 0, index: 1, to: 1))
        XCTAssertEqual(game.state.columns[1].map(\.rank), [.nine, .eight, .seven, .six])
        XCTAssertEqual(game.state.columns[0].count, 1)
        XCTAssertTrue(game.state.columns[0][0].isFaceUp)
        XCTAssertEqual(outcome.revealedCardIDs, [hidden.id])
        XCTAssertEqual(game.state.score, 499)
        XCTAssertEqual(game.state.moves, 1)
    }

    func testPartialRunMove() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([t.run(.nine, .five), [t.c(.eight, .hearts)]]))
        try game.perform(.move(from: 0, index: 2, to: 1)) // 7-6-5 onto red 8
        XCTAssertEqual(game.state.columns[0].map(\.rank), [.nine, .eight])
        XCTAssertEqual(game.state.columns[1].map(\.rank), [.eight, .seven, .six, .five])
    }

    func testMixedSuitStackCannotBeLiftedTogether() {
        var t = Table()
        var game = SpiderGame(state: t.state([[t.c(.seven, .hearts), t.c(.six, .spades)], [t.c(.eight)]]))
        XCTAssertFalse(game.canPerform(.move(from: 0, index: 0, to: 1)))
        XCTAssertThrowsError(try game.perform(.move(from: 0, index: 0, to: 1))) {
            XCTAssertEqual($0 as? GameError, .illegalMove)
        }
        XCTAssertEqual(game.state.score, 500, "illegal move costs nothing")
        XCTAssertFalse(game.canUndo)
    }

    func testMoveToEmptyColumn() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([[t.c(.three, up: false)] + t.run(.queen, .ten), []]))
        try game.perform(.move(from: 0, index: 1, to: 1))
        XCTAssertEqual(game.state.columns[1].map(\.rank), [.queen, .jack, .ten])
        XCTAssertTrue(game.state.columns[0][0].isFaceUp)
    }
}
