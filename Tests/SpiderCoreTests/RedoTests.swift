import XCTest
@testable import SpiderCore

final class RedoTests: XCTestCase {
    private func firstMove(_ game: SpiderGame) -> Action {
        game.state.hints().first?.action ?? .deal
    }

    func testRedoReplaysTheUndoneMove() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 3)
        XCTAssertFalse(game.canRedo)
        let action = firstMove(game)
        try game.perform(action)
        let after = game.state
        try game.undo()
        XCTAssertTrue(game.canRedo)
        XCTAssertEqual(game.nextRedo, action)
        try game.redo()
        XCTAssertEqual(game.state.columns, after.columns)
        XCTAssertEqual(game.state.stock, after.stock)
        XCTAssertFalse(game.canRedo)
        XCTAssertTrue(game.canUndo)
        // Score: move (-1), undo (-1), redo counts as a move (-1). Moves counter: 3.
        XCTAssertEqual(game.state.score, GameState.initialScore - 3)
        XCTAssertEqual(game.state.moves, 3)
    }

    func testRedoesInReverseOrderOfUndo() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 3)
        var positions: [[[Card]]] = []
        for _ in 0..<3 {
            try game.perform(firstMove(game))
            positions.append(game.state.columns)
        }
        for _ in 0..<3 { try game.undo() }
        for i in 0..<3 {
            try game.redo()
            XCTAssertEqual(game.state.columns, positions[i])
        }
        XCTAssertThrowsError(try game.redo()) { XCTAssertEqual($0 as? GameError, .nothingToRedo) }
    }

    func testANewActionClearsRedo() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 3)
        try game.perform(firstMove(game))
        try game.undo()
        XCTAssertTrue(game.canRedo)
        try game.perform(.deal)
        XCTAssertFalse(game.canRedo)
    }

    func testRedoADealDealsTheSameCards() throws {
        var game = SpiderGame(difficulty: .twoSuits, seed: 11)
        try game.perform(.deal)
        let dealt = game.state.columns
        try game.undo()
        try game.redo()
        XCTAssertEqual(game.state.columns, dealt)
        XCTAssertEqual(game.state.stock.count, GameState.fullStockCount - 10)
    }

    func testClassicUndoModeStillRedoesWhatItCanUndo() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 3, undoPolicy: .xpClassic)
        try game.perform(.deal)
        XCTAssertFalse(game.canUndo, "classic: a deal clears the history")
        XCTAssertFalse(game.canRedo)
        let move = firstMove(game)
        try game.perform(move)
        try game.undo()
        XCTAssertEqual(game.nextRedo, move)
        try game.redo()
        XCTAssertTrue(game.canUndo)
    }

    func testNoRedoOnceWon() throws {
        var t = Table()
        let state = GameState(difficulty: .oneSuit, seed: 0,
                              columns: [t.run(.king, .two), [t.c(.ace)]] + Array(repeating: [], count: 8),
                              stock: [], completed: Array(repeating: .spades, count: 7))
        var game = SpiderGame(state: state)
        try game.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertTrue(game.state.isWon)
        XCTAssertFalse(game.canRedo)
        XCTAssertThrowsError(try game.redo()) { XCTAssertEqual($0 as? GameError, .gameOver) }
    }

    func testRedoSurvivesSavingAndOldSavesDecode() throws {
        var game = SpiderGame(difficulty: .oneSuit, seed: 3)
        let action = firstMove(game)
        try game.perform(action)
        try game.undo()
        let decoded = try JSONDecoder().decode(SpiderGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(decoded.nextRedo, action)

        // A save from before redo: no redoStack and no action in the undo entries.
        try game.perform(action)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        object["redoStack"] = nil
        var entries = try XCTUnwrap(object["undoStack"] as? [[String: Any]])
        for i in entries.indices { entries[i]["action"] = nil }
        object["undoStack"] = entries
        var old = try JSONDecoder().decode(SpiderGame.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.state, game.state)
        XCTAssertFalse(old.canRedo)
        try old.undo()
        XCTAssertFalse(old.canRedo, "an old entry has nothing to redo")
    }

    func testSessionRedoCountsAsPlayAndCanWin() throws {
        var t = Table()
        let state = GameState(difficulty: .oneSuit, seed: 0,
                              columns: [t.run(.king, .three), [t.c(.two)], [t.c(.ace)]] + Array(repeating: [], count: 7),
                              stock: [], completed: Array(repeating: .spades, count: 7))
        var c = SessionController(options: Options(), statistics: Statistics(), seed: 1)
        c.open(SavedSession(game: SpiderGame(state: state)))
        try c.perform(.move(from: 1, index: 0, to: 0))
        try c.perform(.move(from: 2, index: 0, to: 0))
        XCTAssertTrue(c.game.state.isWon)
        XCTAssertEqual(c.statistics[.oneSuit].won, 1)

        var e = SessionController(options: Options(), statistics: Statistics(), seed: 1)
        e.open(SavedSession(game: SpiderGame(state: state)))
        try e.perform(.move(from: 1, index: 0, to: 0))
        try e.undo()
        try e.redo()
        XCTAssertTrue(e.canUndo)
        try e.perform(.move(from: 2, index: 0, to: 0))
        XCTAssertTrue(e.game.state.isWon)
        XCTAssertEqual(e.statistics[.oneSuit].won, 1)
        let unlocked = e.commitUnlocks(at: 1)
        XCTAssertTrue(unlocked.contains(.firstWin))
        XCTAssertFalse(unlocked.contains(.purist), "redo does not hide the undo")
    }

    func testSessionRedoOfTheWinningMoveRecordsTheWin() throws {
        var t = Table()
        let state = GameState(difficulty: .oneSuit, seed: 0,
                              columns: [t.run(.king, .two), [t.c(.ace)], [t.c(.five, .hearts)]] + Array(repeating: [], count: 7),
                              stock: [], completed: Array(repeating: .spades, count: 7))
        var c = SessionController(options: Options(), statistics: Statistics(), seed: 1)
        c.open(SavedSession(game: SpiderGame(state: state)))
        try c.perform(.move(from: 2, index: 0, to: 3))
        try c.undo()
        XCTAssertTrue(c.canRedo)
        try c.redo()
        try c.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertEqual(c.statistics[.oneSuit].won, 1)
        XCTAssertFalse(c.canRedo)
    }
}
