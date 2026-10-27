import XCTest
@testable import SpiderCore

final class SessionTests: XCTestCase {
    private func controller(_ configure: (inout Options) -> Void = { _ in }) -> SessionController {
        var options = Options()
        configure(&options)
        return SessionController(options: options, statistics: Statistics(), seed: 1)
    }

    private func playOneMove(_ c: inout SessionController) throws {
        if let hint = c.game.state.hints().first { try c.perform(hint.action) } else { try c.perform(.deal) }
    }

    /// A position one move from winning (7 suits done, K..2 + A of spades left).
    private func nearWin() -> SavedSession {
        var t = Table()
        let state = t.state([t.run(.king, .two), [t.c(.ace)]], completed: Array(repeating: .spades, count: 7), pad: false)
        return SavedSession(game: SpiderGame(state: GameState(difficulty: .oneSuit, seed: 0, columns: state.columns,
                                                              stock: [], completed: state.completed,
                                                              score: 1000, moves: 90)))
    }

    func testUntouchedGameIsNotInProgressAndAbandonsFreely() {
        var c = controller()
        XCTAssertFalse(c.needsAbandonConfirmation)
        c.startNewGame(difficulty: .twoSuits, seed: 2)
        XCTAssertEqual(c.statistics[.oneSuit].played, 0, "never-started games are not counted")
        XCTAssertEqual(c.game.state.difficulty, .twoSuits)
        XCTAssertEqual(c.options.difficulty, .twoSuits, "difficulty remembered")
    }

    func testAbandoningAStartedGameCountsAsLossOnce() throws {
        var c = controller()
        try playOneMove(&c)
        XCTAssertTrue(c.needsAbandonConfirmation)
        c.startNewGame(difficulty: .oneSuit, seed: 5)
        XCTAssertEqual(c.statistics[.oneSuit].played, 1)
        XCTAssertEqual(c.statistics[.oneSuit].won, 0)
        XCTAssertEqual(c.statistics[.oneSuit].currentLossStreak, 1)
        XCTAssertFalse(c.needsAbandonConfirmation)
    }

    func testRestartReplaysSameDealAndCountsLoss() throws {
        var c = controller { $0.difficulty = .fourSuits }
        let original = c.game.state
        try playOneMove(&c)
        c.restart()
        XCTAssertEqual(c.game.state, original)
        XCTAssertEqual(c.statistics[.fourSuits].played, 1)
        c.restart()
        XCTAssertEqual(c.statistics[.fourSuits].played, 1, "restarting an untouched game is free")
    }

    func testWinIsRecordedOnceWithScoreAndBlocksUndo() throws {
        var c = controller()
        c.open(nearWin())
        XCTAssertTrue(c.needsAbandonConfirmation)
        let outcome = try c.perform(.move(from: 1, index: 0, to: 0))
        XCTAssertTrue(outcome.didWin)
        let s = c.statistics[.oneSuit]
        XCTAssertEqual(s.won, 1)
        XCTAssertEqual(s.played, 1)
        XCTAssertEqual(s.highScore, 1099)
        XCTAssertFalse(c.canUndo)
        XCTAssertThrowsError(try c.undo())
        XCTAssertFalse(c.needsAbandonConfirmation)
        c.startNewGame(difficulty: .oneSuit, seed: 3)
        XCTAssertEqual(c.statistics[.oneSuit].played, 1, "a won game is not also a loss")
    }

    func testOpeningSavedGameAbandonsCurrentAndKeepsUndoHistory() throws {
        var c = controller()
        try playOneMove(&c)
        var other = SessionController(options: Options(), statistics: Statistics(), seed: 99)
        try other.perform(.deal)
        c.open(other.session)
        XCTAssertEqual(c.statistics[.oneSuit].played, 1)
        XCTAssertEqual(c.game.state, other.game.state)
        XCTAssertTrue(c.canUndo)
        try c.undo()
        XCTAssertEqual(c.game.state.stock.count, 50)
    }

    func testOptionsUndoPolicyAppliesToCurrentAndOpenedGames() throws {
        var c = controller()
        c.options.undoPolicy = .xpClassic
        XCTAssertEqual(c.game.undoPolicy, .xpClassic)
        try c.perform(.deal)
        XCTAssertFalse(c.canUndo, "classic undo stops at deals")
        var saved = SavedSession(game: SpiderGame(difficulty: .oneSuit, seed: 4, undoPolicy: .unlimited))
        saved.resultRecorded = false
        c.open(saved)
        XCTAssertEqual(c.game.undoPolicy, .xpClassic)
    }

    func testQuitDecisionFollowsOptions() throws {
        var c = controller()
        XCTAssertEqual(c.quitDecision, .nothing, "nothing to save before the first move")
        try playOneMove(&c)
        XCTAssertEqual(c.quitDecision, .save)
        c.options.saveOnExit = .prompt
        XCTAssertEqual(c.quitDecision, .ask)
        c.options.saveOnExit = .never
        XCTAssertEqual(c.quitDecision, .discardAsLoss)
        c.quitWithoutSaving()
        XCTAssertEqual(c.statistics[.oneSuit].played, 1)
        XCTAssertEqual(c.quitDecision, .nothing, "already counted")
    }

    func testLaunchDecision() {
        var o = Options()
        XCTAssertEqual(SessionController.launchDecision(options: o, hasSavedGame: false), .newGame)
        XCTAssertEqual(SessionController.launchDecision(options: o, hasSavedGame: true), .resumeSaved)
        o.openOnStart = .prompt
        XCTAssertEqual(SessionController.launchDecision(options: o, hasSavedGame: true), .ask)
        o.openOnStart = .never
        XCTAssertEqual(SessionController.launchDecision(options: o, hasSavedGame: true), .discardSaved)
    }

    func testDiscardingSavedGameCountsLossOnlyIfInProgress() throws {
        var c = controller()
        c.discard(SavedSession(game: SpiderGame(difficulty: .twoSuits, seed: 1)))
        XCTAssertEqual(c.statistics[.twoSuits].played, 0)
        var started = SavedSession(game: SpiderGame(difficulty: .twoSuits, seed: 1))
        try started.game.perform(.deal)
        c.discard(started)
        XCTAssertEqual(c.statistics[.twoSuits].played, 1)
        started.resultRecorded = true
        c.discard(started)
        XCTAssertEqual(c.statistics[.twoSuits].played, 1)
    }

    func testResetStatisticsClearsOneDifficulty() throws {
        var c = controller()
        try playOneMove(&c)
        c.startNewGame(difficulty: .twoSuits, seed: 1)
        try playOneMove(&c)
        c.startNewGame(difficulty: .twoSuits, seed: 2)
        c.resetStatistics(.oneSuit)
        XCTAssertEqual(c.statistics[.oneSuit].played, 0)
        XCTAssertEqual(c.statistics[.twoSuits].played, 1)
    }

    func testStatisticsJSONIsKeyedBySuitCount() throws {
        var stats = Statistics()
        stats[.fourSuits].recordWin(score: 700)
        stats[.oneSuit].recordLoss()
        let data = try JSONEncoder().encode(stats)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(Set(object?.keys ?? [:].keys), ["1", "4"])
        XCTAssertEqual(try JSONDecoder().decode(Statistics.self, from: data), stats)
    }

    func testOptionsDecodeToleratesMissingAndUnknownFields() throws {
        let json = #"{"animationsEnabled": false, "saveOnExit": "bogus", "future": 1}"#
        let o = try JSONDecoder().decode(Options.self, from: Data(json.utf8))
        XCTAssertFalse(o.animationsEnabled)
        XCTAssertEqual(o.saveOnExit, .always)
        XCTAssertEqual(o.difficulty, .oneSuit)
        var custom = Options()
        custom.openOnStart = .prompt
        custom.undoPolicy = .xpClassic
        XCTAssertEqual(try JSONDecoder().decode(Options.self, from: JSONEncoder().encode(custom)), custom)
    }
}

final class OptionsSoundTests: XCTestCase {
    func testSoundsOffByDefaultAndOldFilesStillDecode() throws {
        XCTAssertFalse(Options().soundsEnabled)
        let old = #"{"difficulty": 2, "animationsEnabled": true}"#
        let o = try JSONDecoder().decode(Options.self, from: Data(old.utf8))
        XCTAssertFalse(o.soundsEnabled)
        XCTAssertEqual(o.difficulty, .twoSuits)
        var on = Options()
        on.soundsEnabled = true
        XCTAssertTrue(try JSONDecoder().decode(Options.self, from: JSONEncoder().encode(on)).soundsEnabled)
    }
}
