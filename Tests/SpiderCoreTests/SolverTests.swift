import XCTest

@testable import SpiderCore

final class SolverTests: XCTestCase {
    /// 1-suit deals the solver finds quickly (measured with `SpiderTools bench 1 ...`).
    static let easyOneSuitSeeds: [UInt64] = [12345, 11_400_714_819_323_210_830, 4_354_685_564_936_857_699]

    private func solution(
        _ difficulty: Difficulty, _ seed: UInt64, nodes: Int = 60_000,
        file: StaticString = #filePath, line: UInt = #line
    ) -> [Action]? {
        let report = Solver.solve(difficulty: difficulty, seed: seed, budget: SolverBudget(maxNodes: nodes))
        guard case .solved(let actions) = report.result else {
            XCTFail("seed \(seed) not solved: \(report.result) after \(report.nodes) nodes", file: file, line: line)
            return nil
        }
        return actions
    }

    func testSolvesEasyOneSuitSeeds() {
        for seed in Self.easyOneSuitSeeds {
            guard let actions = solution(.oneSuit, seed) else { continue }
            XCTAssertTrue(Solver.verify(difficulty: .oneSuit, seed: seed, actions: actions))
        }
    }

    func testEverySolutionStepIsLegalAndAFreshGameEndsWon() throws {
        let seed = Self.easyOneSuitSeeds[0]
        let actions = try XCTUnwrap(solution(.oneSuit, seed))
        var game = SpiderGame(difficulty: .oneSuit, seed: seed)
        for (i, action) in actions.enumerated() {
            XCTAssertFalse(game.state.isWon, "won early at step \(i)")
            XCTAssertTrue(game.canPerform(action), "illegal step \(i): \(action)")
            try game.perform(action)
        }
        XCTAssertTrue(game.state.isWon)
        XCTAssertEqual(game.state.completed.count, GameState.suitsToWin)
    }

    func testDeterministic() {
        let seed = Self.easyOneSuitSeeds[1]
        let a = Solver.solve(difficulty: .oneSuit, seed: seed, budget: SolverBudget(maxNodes: 60_000))
        let b = Solver.solve(difficulty: .oneSuit, seed: seed, budget: SolverBudget(maxNodes: 60_000))
        XCTAssertEqual(a, b)
    }

    func testVerifyRejectsIllegalOrUnfinishedLines() throws {
        let seed = Self.easyOneSuitSeeds[0]
        let actions = try XCTUnwrap(solution(.oneSuit, seed))
        XCTAssertFalse(Solver.verify(difficulty: .oneSuit, seed: seed, actions: Array(actions.dropLast())))
        XCTAssertFalse(
            Solver.verify(difficulty: .oneSuit, seed: seed, actions: [.move(from: 0, index: 0, to: 1)] + actions))
    }

    func testFinishesANearlyWonPosition() throws {
        var t = Table()
        let s = t.state(
            [t.run(.king, .three), [t.c(.two), t.c(.ace)]], completed: Array(repeating: .spades, count: 7),
            pad: false)
        let report = Solver.solve(s, budget: SolverBudget(maxNodes: 1_000))
        guard case .solved(let actions) = report.result else { return XCTFail("\(report.result)") }
        var game = SpiderGame(state: s)
        for action in actions { try game.perform(action) }
        XCTAssertTrue(game.state.isWon)
    }

    func testReportsUnsolvableWhenNothingCanMove() {
        var t = Table()
        // Ten kings of clubs, nothing else: no moves, no stock, not won.
        let s = t.state([], completed: Array(repeating: .spades, count: 6))
        XCTAssertEqual(Solver.solve(s, budget: SolverBudget(maxNodes: 1_000)).result, SolverResult.unsolvable)
    }

    func testBudgetAndStopHookGiveUp() {
        let seed = Self.easyOneSuitSeeds[0]
        XCTAssertEqual(
            Solver.solve(difficulty: .fourSuits, seed: seed, budget: SolverBudget(maxNodes: 50)).result,
            SolverResult.gaveUp)
        let stopped = Solver.solve(
            difficulty: .fourSuits, seed: seed, budget: SolverBudget(maxNodes: 1_000_000),
            shouldStop: { true })
        XCTAssertEqual(stopped.result, SolverResult.gaveUp)
        XCTAssertLessThanOrEqual(stopped.nodes, 1_024)
    }

    func testBundledSeedsAreWinnable() {
        // A handful of the quicker ones (all were verified when generated; `SpiderTools bundled`
        // re-checks the whole list in release mode).
        let sample: [Difficulty: [UInt64]] = [
            .oneSuit: [0xF9AC4C42EB94C353, 0xFDB6A51F6276E327, 0x39CDFAD77A4DC831],
            .twoSuits: [0x3DBD3222C2D2705B, 0xC6DAD6CF902F144F],
            .fourSuits: [0x7508B238EC0F5E2F],
        ]
        for difficulty in Difficulty.allCases {
            let seeds = WinnableDeals.bundled[difficulty] ?? []
            XCTAssertGreaterThanOrEqual(seeds.count, 20)
            XCTAssertEqual(Set(seeds).count, seeds.count, "no duplicates")
            for seed in sample[difficulty] ?? [] {
                XCTAssertTrue(seeds.contains(seed))
                XCTAssertNotNil(
                    Solver.winningLine(difficulty: difficulty, seed: seed), "bundled \(difficulty) seed \(seed)")
            }
        }
    }

    func testSearchReturnsTheFirstWinnableSeedAndHonoursStop() {
        var candidates: [UInt64] = Self.easyOneSuitSeeds
        let found = WinnableDeals.search(
            difficulty: .oneSuit, nextSeed: { candidates.removeFirst() }, shouldStop: { false })
        XCTAssertEqual(found, Self.easyOneSuitSeeds[0])
        XCTAssertNil(WinnableDeals.search(difficulty: .oneSuit, nextSeed: { 1 }, shouldStop: { true }))
    }

    func testSeedCacheOrderDedupeAndBundledCycle() throws {
        var cache = WinnableSeedCache()
        cache.add(7, for: .oneSuit)
        cache.add(UInt64.max, for: .oneSuit)
        cache.add(7, for: .oneSuit)
        cache.add(9, for: .twoSuits)
        XCTAssertEqual(cache.count(.oneSuit), 2)
        let decoded = try JSONDecoder().decode(WinnableSeedCache.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(decoded, cache, "UInt64 seeds survive JSON exactly")
        XCTAssertEqual(cache.takeReady(.oneSuit), 7)
        XCTAssertEqual(cache.takeReady(.oneSuit), UInt64.max)
        XCTAssertNil(cache.takeReady(.oneSuit))
        XCTAssertNil(cache.takeReady(.fourSuits))
        let bundled = WinnableDeals.bundled[.fourSuits]!
        let firstPass = (0..<bundled.count).map { _ in cache.takeBundled(.fourSuits)! }
        XCTAssertEqual(firstPass, bundled)
        XCTAssertEqual(cache.takeBundled(.fourSuits), bundled[0], "cycles after the last one")
    }

    func testWinnableOptionOffByDefaultAndOldFilesDecode() throws {
        XCTAssertFalse(Options().winnableDealsOnly)
        let old = #"{"difficulty":2,"soundsEnabled":true}"#
        let o = try JSONDecoder().decode(Options.self, from: Data(old.utf8))
        XCTAssertFalse(o.winnableDealsOnly)
        XCTAssertEqual(o.difficulty, .twoSuits)
        var on = Options()
        on.winnableDealsOnly = true
        XCTAssertTrue(try JSONDecoder().decode(Options.self, from: JSONEncoder().encode(on)).winnableDealsOnly)
    }

    func testUpdateCheckOptionOnByDefaultAndOldFilesDecode() throws {
        XCTAssertTrue(Options().checkForUpdatesAutomatically)
        let old = #"{"difficulty":2,"winnableDealsOnly":true}"#
        XCTAssertTrue(try JSONDecoder().decode(Options.self, from: Data(old.utf8)).checkForUpdatesAutomatically)
        var off = Options()
        off.checkForUpdatesAutomatically = false
        XCTAssertFalse(
            try JSONDecoder().decode(Options.self, from: JSONEncoder().encode(off)).checkForUpdatesAutomatically)
    }
}
