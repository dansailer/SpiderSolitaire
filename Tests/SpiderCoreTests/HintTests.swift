import XCTest
@testable import SpiderCore

final class HintTests: XCTestCase {
    func testSameSuitBeforeOtherSuitBeforeEmptyColumn() {
        var t = Table()
        let state = t.state([
            [t.c(.two, up: false), t.c(.five, .hearts)],   // 0: red 5
            [t.c(.six, .clubs)],                           // 1: black 6 (other suit)
            [t.c(.six, .hearts)],                          // 2: red 6 (same suit)
            [t.c(.three, up: false), t.c(.jack)],          // 3: J -> empty
            [],                                            // 4: empty
        ])
        let hints = state.hints()
        XCTAssertEqual(hints.first, Hint(from: 0, index: 1, to: 2, kind: .sameSuit))
        XCTAssertTrue(hints.contains(Hint(from: 0, index: 1, to: 1, kind: .otherSuit)))
        XCTAssertEqual(hints.map(\.kind), hints.map(\.kind).sorted(), "ordered by kind")
        XCTAssertEqual(hints.last?.kind, .emptyColumn)
        XCTAssertTrue(hints.allSatisfy { state.canMove(from: $0.from, index: $0.index, to: $0.to) })
    }

    func testSkipsPointlessShuffles() {
        var t = Table()
        let state = t.state([
            [t.c(.seven, .clubs), t.c(.six, .hearts)],   // 6♥ already on a 7: moving it to 7♠ is pointless
            [t.c(.seven, .spades)],
            [t.c(.eight), t.c(.seven)],                  // same-suit run: never suggest moving 7♠ off 8♠
            [t.c(.eight, .hearts)],
            [t.c(.king)],                                // lone king fills its column: no empty-column hint
            [],
        ], pad: true)
        let hints = state.hints()
        XCTAssertFalse(hints.contains { $0.from == 0 && $0.to == 1 })
        XCTAssertFalse(hints.contains { $0.from == 2 && $0.index == 1 && $0.kind != .emptyColumn })
        XCTAssertFalse(hints.contains { $0.from == 4 })
        // 6♥ onto 7♥ would still be suggested if one existed; moving to the empty column is offered.
        XCTAssertTrue(hints.contains(Hint(from: 0, index: 1, to: 5, kind: .emptyColumn)))
    }

    func testNoHintsWhenBlocked() {
        var t = Table()
        let state = t.state([[t.c(.two)], [t.c(.five)], [t.c(.nine)]], pad: true)
        XCTAssertTrue(state.hints().isEmpty)
        XCTAssertFalse(state.hasLegalMove)
    }

    func testHasLegalMoveIgnoresWholeColumnToEmpty() {
        var t = Table()
        let state = t.state([[t.c(.queen)], [], [t.c(.two)]], pad: false)
        XCTAssertFalse(state.hasLegalMove)
    }

    func testEveryHintInRandomGamesIsLegal() throws {
        for seed in UInt64(0)..<40 {
            for difficulty in Difficulty.allCases {
                var game = SpiderGame(difficulty: difficulty, seed: seed)
                for _ in 0..<60 {
                    let hints = game.state.hints()
                    for hint in hints { XCTAssertTrue(game.canPerform(hint.action), "\(seed) \(hint)") }
                    if let hint = hints.first { try game.perform(hint.action) }
                    else if game.state.canDeal { try game.perform(.deal) }
                    else { break }
                    assertInvariants(game.state)
                }
            }
        }
    }

    private func assertInvariants(_ s: GameState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.tableauCardCount + s.stock.count + s.completed.count * 13, 104, file: file, line: line)
        for column in s.columns where !column.isEmpty {
            XCTAssertTrue(column.last!.isFaceUp, "top card always face up", file: file, line: line)
            if let firstUp = column.firstIndex(where: \.isFaceUp) {
                XCTAssertTrue(column[firstUp...].allSatisfy(\.isFaceUp), "no face-down above face-up", file: file, line: line)
            }
        }
        XCTAssertEqual(s.stock.count % 10, 0, file: file, line: line)
    }
}

final class StuckTests: XCTestCase {
    func testStuckWhenNoHintNoDealNoEmptyColumn() {
        var t = Table()
        let stuck = t.state([[t.c(.two)], [t.c(.five)], [t.c(.nine)]], pad: true)
        XCTAssertTrue(stuck.isStuck)
    }

    func testNotStuckWhenADealIsPossible() {
        var t = Table()
        let canDeal = t.state([[t.c(.two)], [t.c(.five)], [t.c(.nine)]], stock: t.stock(10), pad: true)
        XCTAssertFalse(canDeal.isStuck)
    }

    func testNotStuckWithAnEmptyColumnOrAHint() {
        var t = Table()
        XCTAssertFalse(t.state([[t.c(.two)], []], pad: true).isStuck)
        XCTAssertFalse(t.state([[t.c(.two)], [t.c(.three, .hearts)]], pad: true).isStuck)
    }

    func testWonGameIsNotStuck() {
        let won = GameState(difficulty: .oneSuit, seed: 0,
                            columns: Array(repeating: [Card](), count: 10), stock: [],
                            completed: Array(repeating: .spades, count: 8))
        XCTAssertFalse(won.isStuck)
    }
}
