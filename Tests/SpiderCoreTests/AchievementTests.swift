import XCTest

@testable import SpiderCore

final class AchievementTests: XCTestCase {
    /// One move from winning: 7 suits done, K..2 and an ace of spades left.
    private func nearWin(_ difficulty: Difficulty = .oneSuit, moves: Int = 90, tracker: GameTracker = GameTracker())
        -> SavedSession
    {
        var t = Table()
        let columns = [t.run(.king, .two), [t.c(.ace)]] + Array(repeating: [Card](), count: 8)
        let state = GameState(
            difficulty: difficulty, seed: 0, columns: columns, stock: [],
            completed: Array(repeating: .spades, count: 7), score: 1000, moves: moves)
        var session = SavedSession(game: SpiderGame(state: state))
        session.tracker = tracker
        return session
    }

    private func controller(
        _ session: SavedSession, statistics: Statistics = Statistics(),
        book: AchievementBook = AchievementBook()
    ) -> SessionController {
        var c = SessionController(options: Options(), statistics: statistics, achievements: book, seed: 1)
        c.open(session)
        return c
    }

    private let winningMove = Action.move(from: 1, index: 0, to: 0)

    /// Unlocks from finishing `session`.
    private func unlocks(winning session: SavedSession, statistics: Statistics = Statistics()) throws -> Set<
        AchievementID
    > {
        var c = controller(session, statistics: statistics)
        try c.perform(winningMove)
        XCTAssertTrue(c.game.state.isWon)
        return Set(c.commitUnlocks(at: 1_000))
    }

    func testListIsCompleteAndUnique() {
        XCTAssertEqual(Achievement.all.map(\.id), AchievementID.allCases)
        XCTAssertEqual(Set(Achievement.all.map(\.title)).count, Achievement.all.count)
        XCTAssertEqual(Set(Achievement.all.map(\.emblem)).count, Achievement.all.count, "one emblem each")
        for a in Achievement.all { XCTAssertFalse(a.hint.isEmpty) }
    }

    func testFirstWinAndDifficultyWins() throws {
        let one = try unlocks(winning: nearWin(.oneSuit))
        XCTAssertTrue(one.contains(.firstWin))
        XCTAssertFalse(one.contains(.twoSuitWin))
        XCTAssertTrue(try unlocks(winning: nearWin(.twoSuits)).isSuperset(of: [.firstWin, .twoSuitWin]))
        let four = try unlocks(winning: nearWin(.fourSuits))
        XCTAssertTrue(four.isSuperset(of: [.firstWin, .fourSuitWin]))
        XCTAssertFalse(four.contains(.twoSuitWin))
    }

    func testPuristNeedsNoUndo() throws {
        XCTAssertTrue(try unlocks(winning: nearWin()).contains(.purist))
        var t = GameTracker()
        t.undoCount = 1
        XCTAssertFalse(try unlocks(winning: nearWin(tracker: t)).contains(.purist))
    }

    func testGrandmasterIsFourSuitsWithoutUndo() throws {
        XCTAssertTrue(try unlocks(winning: nearWin(.fourSuits)).contains(.grandmaster))
        XCTAssertFalse(try unlocks(winning: nearWin(.twoSuits)).contains(.grandmaster))
        var t = GameTracker()
        t.undoCount = 3
        XCTAssertFalse(try unlocks(winning: nearWin(.fourSuits, tracker: t)).contains(.grandmaster))
    }

    func testNoPeekingNeedsNoHints() throws {
        XCTAssertTrue(try unlocks(winning: nearWin()).contains(.noPeeking))
        var t = GameTracker()
        t.hintCount = 1
        XCTAssertFalse(try unlocks(winning: nearWin(tracker: t)).contains(.noPeeking))
    }

    func testSpeedsterThresholdsPerDifficulty() throws {
        var t = GameTracker()
        t.elapsedSeconds = 299
        XCTAssertTrue(try unlocks(winning: nearWin(.oneSuit, tracker: t)).contains(.speedster))
        t.elapsedSeconds = 300
        XCTAssertFalse(try unlocks(winning: nearWin(.oneSuit, tracker: t)).contains(.speedster))
        t.elapsedSeconds = 20 * 60
        XCTAssertTrue(try unlocks(winning: nearWin(.fourSuits, tracker: t)).contains(.speedster))
        XCTAssertFalse(try unlocks(winning: nearWin(.twoSuits, tracker: t)).contains(.speedster))
    }

    func testEfficientCountsTheMovesCounter() throws {
        // nearWin's move counter plus the winning move.
        XCTAssertTrue(try unlocks(winning: nearWin(.oneSuit, moves: 149)).contains(.efficient))
        XCTAssertFalse(try unlocks(winning: nearWin(.oneSuit, moves: 150)).contains(.efficient))
        XCTAssertTrue(try unlocks(winning: nearWin(.fourSuits, moves: 299)).contains(.efficient))
    }

    func testUnknownHistoryBlocksOnlyHistoryAchievements() throws {
        var t = GameTracker.unknownHistory
        t.elapsedSeconds = 10
        let got = try unlocks(winning: nearWin(tracker: t))
        XCTAssertTrue(got.contains(.firstWin))
        XCTAssertTrue(got.contains(.efficient))
        XCTAssertTrue(got.isDisjoint(with: [.purist, .noPeeking, .speedster]))
    }

    /// Full stock, a column whose top run completes when the ace drops on it, the ace alone in its column.
    private func beforeFirstDeal(otherColumnEmpties: Bool) -> SavedSession {
        var t = Table()
        var columns: [[Card]] = [[t.c(.nine, up: false)] + t.run(.king, .two), [t.c(.five, up: false), t.c(.ace)]]
        if otherColumnEmpties { columns[1] = [t.c(.ace)] }
        while columns.count < GameState.columnCount { columns.append([t.c(.king, .hearts)]) }
        let state = GameState(difficulty: .oneSuit, seed: 0, columns: columns, stock: t.stock(GameState.fullStockCount))
        return SavedSession(game: SpiderGame(state: state))
    }

    func testCleanSweepAndEmptyHandedBeforeTheFirstDeal() throws {
        var c = controller(beforeFirstDeal(otherColumnEmpties: false))
        try c.perform(.move(from: 1, index: 1, to: 0))
        XCTAssertEqual(c.commitUnlocks(at: 5), [.cleanSweep], "suit done; the 9 and 5 were revealed, no empty column")

        var d = controller(beforeFirstDeal(otherColumnEmpties: true))
        try d.perform(winningMove)
        XCTAssertEqual(Set(d.commitUnlocks(at: 5)), [.cleanSweep, .emptyHanded])
    }

    func testNothingBeforeFirstDealOnceDealt() throws {
        var session = beforeFirstDeal(otherColumnEmpties: true)
        var state = session.game.state
        state.stock.removeLast(10)
        session = SavedSession(game: SpiderGame(state: state))
        var c = controller(session)
        try c.perform(winningMove)
        XCTAssertEqual(c.commitUnlocks(at: 5), [])
    }

    func testStreaksTotalsAndCentury() throws {
        var stats = Statistics()
        for _ in 0..<9 { stats[.twoSuits].recordWin(score: 900) }
        for _ in 0..<15 { stats[.oneSuit].recordWin(score: 900) }
        stats[.oneSuit].recordLoss()
        stats[.oneSuit].recordWin(score: 900)
        // 25 won so far (9 two-suit streak, one-suit streak 1); a 2-suit win makes it 26 and a 10 streak.
        let got = try unlocks(winning: nearWin(.twoSuits), statistics: stats)
        XCTAssertTrue(got.isSuperset(of: [.hatTrick, .onARoll, .seasoned]))
        XCTAssertFalse(got.contains(.century))

        var few = Statistics()
        few[.oneSuit].recordWin(score: 900)
        XCTAssertFalse(try unlocks(winning: nearWin(.twoSuits), statistics: few).contains(.hatTrick))
        few[.twoSuits].recordWin(score: 900)
        few[.twoSuits].recordWin(score: 900)
        XCTAssertTrue(try unlocks(winning: nearWin(.twoSuits), statistics: few).contains(.hatTrick))
    }

    func testCenturyCountsLossesToo() throws {
        var stats = Statistics()
        for _ in 0..<99 { stats[.fourSuits].recordLoss() }
        var c = SessionController(options: Options(), statistics: stats, seed: 3)
        if let hint = c.game.state.hints().first { try c.perform(hint.action) } else { try c.perform(.deal) }
        XCTAssertFalse(c.commitUnlocks(at: 1).contains(.century))
        c.startNewGame(difficulty: .oneSuit, seed: 4) // abandons: the 100th game
        XCTAssertEqual(c.commitUnlocks(at: 2), [.century])
    }

    func testAlreadyUnlockedIsNotRepeatedAndDateIsKept() throws {
        var book = AchievementBook()
        book.unlocked[.firstWin] = 42
        var c = controller(nearWin(), book: book)
        try c.perform(winningMove)
        let got = c.commitUnlocks(at: 1_000)
        XCTAssertFalse(got.contains(.firstWin))
        XCTAssertTrue(got.contains(.purist))
        XCTAssertEqual(c.achievements.unlocked[.firstWin], 42)
        XCTAssertEqual(c.achievements.unlocked[.purist], 1_000)
        XCTAssertEqual(c.commitUnlocks(at: 2_000), [], "pending list is emptied")
    }

    func testTrackerCountsUndoHintsAndPlayTime() throws {
        var c = SessionController(options: Options(), statistics: Statistics(), seed: 1)
        c.addPlayTime(2.5)
        try c.perform(c.game.state.hints().first?.action ?? .deal)
        try c.undo()
        c.noteHint()
        c.addPlayTime(1)
        c.addPlayTime(-5)
        XCTAssertEqual(c.session.tracker.undoCount, 1)
        XCTAssertEqual(c.session.tracker.hintCount, 1)
        XCTAssertEqual(c.session.tracker.elapsedSeconds, 3.5)
        c.restart()
        XCTAssertEqual(c.session.tracker, GameTracker(), "a restart starts a fresh record")
    }

    func testClockStopsOnceWon() throws {
        var c = controller(nearWin())
        c.addPlayTime(10)
        try c.perform(winningMove)
        XCTAssertFalse(c.isClockRunning)
        c.addPlayTime(10)
        XCTAssertEqual(c.session.tracker.elapsedSeconds, 10)
    }

    func testDiscardedSavedGameCountsTowardCentury() throws {
        var stats = Statistics()
        for _ in 0..<99 { stats[.oneSuit].recordLoss() }
        var c = SessionController(options: Options(), statistics: stats, seed: 3)
        var other = SessionController(options: Options(), statistics: Statistics(), seed: 5)
        try other.perform(other.game.state.hints().first?.action ?? .deal)
        c.discard(other.session)
        XCTAssertEqual(c.commitUnlocks(at: 1), [.century])
    }

    // MARK: Persistence

    func testBookJSONIsKeyedByNameAndSkipsUnknownEntries() throws {
        var book = AchievementBook()
        book.unlocked[.hatTrick] = 1_767_225_600
        let data = try JSONEncoder().encode(book)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Double])
        XCTAssertEqual(object, ["hatTrick": 1_767_225_600])
        let json = #"{"hatTrick": 1767225600, "fromTheFuture": 5, "purist": "bad"}"#
        XCTAssertEqual(try JSONDecoder().decode(AchievementBook.self, from: Data(json.utf8)), book)
    }

    func testOldSavedGameWithoutTrackerDecodesWithUnknownHistory() throws {
        let saved = SavedSession(game: SpiderGame(difficulty: .twoSuits, seed: 8))
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        XCTAssertNotNil(object["tracker"])
        object["tracker"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SavedSession.self, from: old)
        XCTAssertEqual(decoded.game.state, saved.game.state)
        XCTAssertFalse(decoded.tracker.isComplete)

        var tracked = saved
        tracked.tracker.elapsedSeconds = 61
        tracked.tracker.undoCount = 2
        let roundTrip = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(tracked))
        XCTAssertEqual(roundTrip.tracker, tracked.tracker)
    }
}
