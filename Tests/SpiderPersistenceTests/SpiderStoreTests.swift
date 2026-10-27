import Foundation
import SpiderCore
import XCTest

@testable import SpiderPersistence

final class SpiderStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spider-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDefaultsWhenNothingSaved() {
        let store = SpiderStore(directory: dir)
        XCTAssertEqual(store.loadStatistics(), Statistics())
        XCTAssertEqual(store.loadOptions(), Options())
        XCTAssertFalse(store.hasSavedGame)
        XCTAssertNil(store.takeSavedGame())
    }

    func testStatisticsAndOptionsRoundTripAndCreateFolder() throws {
        let store = SpiderStore(directory: dir)
        var stats = Statistics()
        stats[.twoSuits].recordWin(score: 950)
        var options = Options()
        options.animationsEnabled = false
        options.saveOnExit = .prompt
        try store.saveStatistics(stats)
        try store.saveOptions(options)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("statistics.json").path))
        let reopened = SpiderStore(directory: dir)
        XCTAssertEqual(reopened.loadStatistics(), stats)
        XCTAssertEqual(reopened.loadOptions(), options)
    }

    func testSavedGameKeepsUndoHistoryAndIsConsumedOnOpen() throws {
        let store = SpiderStore(directory: dir)
        var game = SpiderGame(difficulty: .fourSuits, seed: 77)
        try game.perform(.deal)
        if let hint = game.state.hints().first { try game.perform(hint.action) }
        try store.saveGame(SavedSession(game: game))
        XCTAssertTrue(store.hasSavedGame)
        XCTAssertNotNil(store.peekSavedGame())
        XCTAssertTrue(store.hasSavedGame, "peek does not consume")

        var loaded = try XCTUnwrap(store.takeSavedGame())
        XCTAssertFalse(store.hasSavedGame, "opening uses up the slot")
        XCTAssertEqual(loaded.game.state, game.state)
        XCTAssertEqual(loaded.game.undoDepth, game.undoDepth)
        while loaded.game.canUndo { try loaded.game.undo() }
        XCTAssertEqual(loaded.game.state.columns, SpiderGame(difficulty: .fourSuits, seed: 77).state.columns)
    }

    func testSavingOverwritesTheSingleSlot() throws {
        let store = SpiderStore(directory: dir)
        try store.saveGame(SavedSession(game: SpiderGame(difficulty: .oneSuit, seed: 1)))
        try store.saveGame(SavedSession(game: SpiderGame(difficulty: .twoSuits, seed: 2)))
        XCTAssertEqual(store.takeSavedGame()?.game.state.difficulty, .twoSuits)
    }

    func testCorruptOrFutureSaveIsIgnoredAndRemoved() throws {
        let store = SpiderStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("savedgame.json")
        try Data("{not json".utf8).write(to: file)
        XCTAssertTrue(store.hasSavedGame)
        XCTAssertNil(store.takeSavedGame())
        XCTAssertFalse(store.hasSavedGame)

        var future = SavedSession(game: SpiderGame(difficulty: .oneSuit, seed: 1))
        future.version = SavedSession.currentVersion + 1
        try store.saveGame(future)
        XCTAssertNil(store.peekSavedGame())

        try Data("garbage".utf8).write(to: dir.appendingPathComponent("statistics.json"))
        XCTAssertEqual(store.loadStatistics(), Statistics(), "unreadable stats fall back to empty")
    }

    func testDefaultDirectoryEndsInAppFolder() {
        XCTAssertEqual(SpiderStore.defaultDirectory().lastPathComponent, "SpiderSolitaire")
    }

    /// Launch → play → quit (always save) → relaunch resumes the exact position.
    func testQuitAndResumeFlow() throws {
        let store = SpiderStore(directory: dir)
        var c = SessionController(options: store.loadOptions(), statistics: store.loadStatistics(), seed: 12)
        try c.perform(.deal)
        XCTAssertEqual(c.quitDecision, .save)
        try store.saveGame(c.session)
        try store.saveStatistics(c.statistics)

        let options = store.loadOptions()
        XCTAssertEqual(
            SessionController.launchDecision(options: options, hasSavedGame: store.hasSavedGame), .resumeSaved)
        var relaunched = SessionController(options: options, statistics: store.loadStatistics(), seed: 999)
        relaunched.open(try XCTUnwrap(store.takeSavedGame()))
        XCTAssertEqual(relaunched.game.state, c.game.state)
        XCTAssertEqual(relaunched.statistics[.oneSuit].played, 0, "resuming is not a loss")
        XCTAssertTrue(relaunched.canUndo)
    }

    func testAchievementsAndWinnableSeedsRoundTrip() throws {
        let store = SpiderStore(directory: dir)
        XCTAssertEqual(store.loadAchievements(), AchievementBook())
        XCTAssertEqual(store.loadWinnableSeeds(), WinnableSeedCache())

        var book = AchievementBook()
        book.unlocked[.firstWin] = 1_767_225_600.5
        book.unlocked[.century] = 1_800_000_000
        try store.saveAchievements(book)
        XCTAssertEqual(SpiderStore(directory: dir).loadAchievements(), book)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("achievements.json").path))

        var cache = WinnableSeedCache()
        cache.add(0xFEDC_BA98_7654_3210, for: .fourSuits)
        _ = cache.takeBundled(.oneSuit)
        try store.saveWinnableSeeds(cache)
        var loaded = SpiderStore(directory: dir).loadWinnableSeeds()
        XCTAssertEqual(loaded, cache)
        XCTAssertEqual(loaded.takeReady(.fourSuits), 0xFEDC_BA98_7654_3210)
        XCTAssertEqual(loaded.takeBundled(.oneSuit), WinnableDeals.bundled[.oneSuit]?[1], "bundled position kept")
    }

    func testCorruptAchievementsFileGivesEmptyBook() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: dir.appendingPathComponent("achievements.json"))
        XCTAssertEqual(SpiderStore(directory: dir).loadAchievements(), AchievementBook())
    }
}
