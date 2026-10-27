import XCTest

@testable import SpiderCore

final class UndoAndScoringTests: XCTestCase {
    func testUndoRestoresPositionAndCostsAPoint() throws {
        var game = SpiderGame(difficulty: .fourSuits, seed: 8)
        let start = game.state
        let hint = try XCTUnwrap(game.state.hints().first, "seed 8 has an opening move")
        try game.perform(hint.action)
        XCTAssertEqual(game.state.score, 499)
        try game.undo()
        XCTAssertEqual(game.state.columns, start.columns)
        XCTAssertEqual(game.state.stock, start.stock)
        XCTAssertEqual(game.state.score, 498, "move penalty kept, plus 1 for undo")
        XCTAssertEqual(game.state.moves, 2)
        XCTAssertFalse(game.canUndo)
        XCTAssertThrowsError(try game.undo()) { XCTAssertEqual($0 as? GameError, .nothingToUndo) }
    }

    func testUndoDealReturnsCardsToStock() throws {
        var game = SpiderGame(difficulty: .twoSuits, seed: 21)
        let start = game.state
        try game.perform(.deal)
        try game.undo()
        XCTAssertEqual(game.state.stock, start.stock)
        XCTAssertEqual(game.state.columns, start.columns)
        XCTAssertEqual(game.state.score, 499, "deal is free, undo costs 1")
    }

    func testUndoCompletedSuitRemovesBonusAndRestoresCards() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([[t.c(.four, up: false)] + t.run(.king, .two), [t.c(.ace)]]))
        let start = game.state
        try game.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertEqual(game.state.score, 599)
        try game.undo()
        XCTAssertEqual(game.state.columns, start.columns, "face-down card flips back too")
        XCTAssertTrue(game.state.completed.isEmpty)
        XCTAssertEqual(game.state.score, 498)
    }

    func testUnlimitedUndoGoesBackToStart() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 4)
        let start = game.state
        var actions = 0
        for _ in 0..<30 {
            if let hint = game.state.hints().first {
                try game.perform(hint.action)
            } else if game.state.canDeal {
                try game.perform(.deal)
            } else {
                break
            }
            actions += 1
        }
        XCTAssertEqual(game.undoDepth, actions)
        while game.canUndo { try game.undo() }
        XCTAssertEqual(game.state.columns, start.columns)
        XCTAssertEqual(game.state.stock, start.stock)
    }

    func testXPClassicUndoStopsAtDeal() throws {
        var game = SpiderGame(difficulty: .fourSuits, seed: 8, undoPolicy: .xpClassic)
        if let hint = game.state.hints().first { try game.perform(hint.action) }
        XCTAssertTrue(game.canUndo)
        try game.perform(.deal)
        XCTAssertFalse(game.canUndo, "deal is a barrier in XP")
    }

    func testXPClassicUndoStopsAtCompletedSuit() throws {
        var t = Table()
        var game = SpiderGame(state: t.state([t.run(.king, .two), [t.c(.ace)]]), undoPolicy: .xpClassic)
        try game.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertFalse(game.canUndo)
    }

    func testScoreCanGoNegative() throws {
        var t = Table()
        var state = t.state([[t.c(.five)], [t.c(.six, .hearts)], [t.c(.six, .clubs)]])
        state.score = 1
        var game = SpiderGame(state: state)
        try game.perform(.move(from: 0, index: 0, to: 1))
        try game.perform(.move(from: 1, index: 1, to: 2))
        XCTAssertEqual(game.state.score, -1)
    }

    func testGameRoundTripsThroughCodable() throws {
        var game = SpiderGame(difficulty: .twoSuits, seed: 77)
        try game.perform(.deal)
        let data = try JSONEncoder().encode(game)
        var restored = try JSONDecoder().decode(SpiderGame.self, from: data)
        XCTAssertEqual(restored.state, game.state)
        XCTAssertTrue(restored.canUndo, "undo history is saved too")
        try restored.undo()
        XCTAssertEqual(restored.state.stock.count, 50)
    }

    func testStatistics() {
        var stats = Statistics()
        stats[.oneSuit].recordWin(score: 1100)
        stats[.oneSuit].recordWin(score: 900)
        stats[.oneSuit].recordLoss()
        let s = stats[.oneSuit]
        XCTAssertEqual(s.played, 3)
        XCTAssertEqual(s.won, 2)
        XCTAssertEqual(s.highScore, 1100)
        XCTAssertEqual(s.winPercentage, 67)
        XCTAssertEqual(s.longestWinStreak, 2)
        XCTAssertEqual(s.currentWinStreak, 0)
        XCTAssertEqual(s.currentLossStreak, 1)
        XCTAssertEqual(stats[.fourSuits].played, 0)
    }
}
