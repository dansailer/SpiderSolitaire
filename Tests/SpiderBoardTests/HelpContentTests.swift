import XCTest
import SpiderCore
@testable import SpiderBoard

final class HelpContentTests: XCTestCase {
    private func text(_ id: HelpSection.ID) -> String { HelpContent.markdown(HelpContent.section(id)) }

    private func tableRows(_ id: HelpSection.ID) -> [[String]] {
        HelpContent.section(id).blocks.flatMap { block -> [[String]] in
            if case .table(_, let rows) = block { return rows }
            return []
        }
    }

    func testSectionsInOrderWithTitles() {
        XCTAssertEqual(HelpContent.sections.map(\.id), HelpSection.ID.allCases)
        XCTAssertEqual(HelpContent.sections.map(\.title),
                       ["Rules", "Scoring", "Tips", "Achievements", "Keyboard Shortcuts"])
        for section in HelpContent.sections { XCTAssertFalse(section.blocks.isEmpty) }
    }

    func testEveryMenuShortcutIsListed() {
        let rows = tableRows(.shortcuts)
        for command in MenuCommand.allCases {
            guard let shortcut = command.shortcut else { continue }
            XCTAssertTrue(rows.contains { $0[0] == shortcut.description && $0[1].hasSuffix(command.title) },
                          "\(command) \(shortcut) missing from Keyboard Shortcuts")
        }
        for standard in HelpContent.standardShortcuts {
            XCTAssertTrue(rows.contains { $0 == [standard.shortcut.description, standard.title] })
            XCTAssertNotNil(MenuCommand.reservedShortcuts[standard.shortcut], "standard shortcuts are reserved ones")
        }
        let keys = rows.map { $0[0] }
        XCTAssertEqual(Set(keys).count, keys.count, "each shortcut listed once")
    }

    func testEveryAchievementIsListedWithItsCondition() {
        let rows = tableRows(.achievements)
        XCTAssertEqual(rows, Achievement.all.map { [$0.title, $0.hint] })
    }

    func testScoringNumbersMatchTheRules() {
        let r = ScoringRules()
        let rows = tableRows(.scoring)
        XCTAssertEqual(rows[0][1], "+\(r.completedSuitBonus)")
        XCTAssertEqual(rows[1][1], "−\(r.movePenalty)")
        XCTAssertTrue(rows[2][1].hasPrefix("−\(r.undoPenalty)"))
        XCTAssertTrue(rows[3][1].hasPrefix("−\(r.movePenalty)"))
        XCTAssertEqual(rows[4][1], r.dealPenalty == 0 ? "free" : "−\(r.dealPenalty)")
        let t = text(.scoring)
        XCTAssertTrue(t.contains("starts at \(GameState.initialScore) points"))
        XCTAssertTrue(t.contains("score \(GameState.initialScore + GameState.suitsToWin * r.completedSuitBonus) points"))
    }

    /// The help's "final score = 1305 − Moves" claim, checked on a real won game (with an undo and a redo).
    func testFinalScoreFormulaHoldsOnARealWin() throws {
        let seed: UInt64 = 12345
        guard case .solved(let line) = Solver.solve(difficulty: .oneSuit, seed: seed,
                                                    budget: SolverBudget(maxNodes: 60_000)).result else {
            return XCTFail("solver")
        }
        var game = SpiderGame(difficulty: .oneSuit, seed: seed)
        try game.perform(line[0])
        try game.undo()
        try game.redo()
        for action in line.dropFirst() { try game.perform(action) }
        XCTAssertTrue(game.state.isWon)
        let deals = GameState.fullStockCount / GameState.columnCount
        let best = GameState.initialScore + GameState.suitsToWin * ScoringRules().completedSuitBonus
        XCTAssertEqual(game.state.score, best + deals - game.state.moves)
        XCTAssertTrue(text(.scoring).contains("final score is \(best + deals) minus the Moves counter"))
    }

    func testRulesNumbersAndNoSpiders() {
        let rules = text(.rules)
        XCTAssertTrue(rules.contains("\(GameState.columnCount) columns"))
        XCTAssertTrue(rules.contains("\(GameState.fullStockCount) cards wait in the stock"))
        XCTAssertTrue(rules.contains("enough for 5 more deals"))
        for section in HelpContent.sections {
            let t = HelpContent.markdown(section).lowercased()
            XCTAssertFalse(t.replacingOccurrences(of: "spider solitaire", with: "").contains("spider"),
                           "\(section.title): no spiders")
            XCTAssertFalse(t.contains("..."), "use the ellipsis character")
        }
    }

    func testTipsUseTheRealShortcuts() {
        let tips = text(.tips)
        XCTAssertTrue(tips.contains(MenuCommand.showHint.shortcut!.description))
        XCTAssertTrue(tips.contains(MenuCommand.undo.shortcut!.description))
        XCTAssertTrue(tips.contains(MenuCommand.redo.shortcut!.description))
    }

    func testHelpCommandIsTheStandardOne() {
        XCTAssertEqual(MenuCommand.help.title, "Spider Solitaire Help")
        XCTAssertEqual(MenuCommand.help.shortcut?.description, "⌘?")
        XCTAssertEqual(MenuCommand.help.menu, .help)
    }
}
