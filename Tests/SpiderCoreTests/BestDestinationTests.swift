import XCTest

@testable import SpiderCore

final class BestDestinationTests: XCTestCase {
    func testPrefersSameSuitThenOtherSuitThenEmpty() {
        var t = Table()
        let state = t.state([
            [t.c(.two, up: false), t.c(.five, .hearts)],
            [t.c(.six, .clubs)],
            [t.c(.six, .hearts)],
            [],
        ])
        XCTAssertEqual(state.bestDestination(from: 0, index: 1), 2)

        let noSameSuit = t.state([[t.c(.two, up: false), t.c(.five, .hearts)], [], [t.c(.six, .clubs)]])
        XCTAssertEqual(noSameSuit.bestDestination(from: 0, index: 1), 2, "card beats empty column")

        let onlyEmpty = t.state([[t.c(.two, up: false), t.c(.five, .hearts)], [], [t.c(.nine)]])
        XCTAssertEqual(onlyEmpty.bestDestination(from: 0, index: 1), 1)
    }

    func testNearestToTheRightWithWrapAround() {
        var t = Table()
        let state = t.state([
            [t.c(.six, .clubs)], // 0
            [t.c(.ace)], // 1
            [t.c(.three)], // 2
            [t.c(.five, .hearts)], // 3 source
            [t.c(.nine)], // 4
            [t.c(.six, .diamonds)], // 5
        ])
        XCTAssertEqual(state.bestDestination(from: 3, index: 0), 5)
        let wrap = t.state([[t.c(.six, .clubs)], [t.c(.ace)], [t.c(.three)], [t.c(.five, .hearts)]])
        XCTAssertEqual(wrap.bestDestination(from: 3, index: 0), 0)
    }

    func testNilForUnmovableOrPointless() {
        var t = Table()
        let state = t.state([[t.c(.seven, .hearts), t.c(.six, .spades)], [t.c(.queen)], [], [t.c(.two)]], pad: false)
        XCTAssertNil(state.bestDestination(from: 0, index: 0), "mixed suits can't be lifted")
        XCTAssertNil(state.bestDestination(from: 1, index: 0), "lone card to empty column is pointless")
        XCTAssertNil(state.bestDestination(from: 2, index: 0), "empty column")
        XCTAssertNil(state.bestDestination(from: 3, index: 0), "no target")
    }

    func testSameSuitTargetWithTheLongestRunWins() {
        var t = Table()
        let state = t.state([
            [t.c(.two, up: false), t.c(.five, .hearts)],
            [t.c(.six, .hearts)],
            [t.c(.eight, .hearts), t.c(.seven, .hearts), t.c(.six, .hearts)],
            [t.c(.seven, .clubs), t.c(.six, .hearts)],
        ])
        XCTAssertEqual(state.bestDestination(from: 0, index: 1), 2, "8♥ 7♥ 6♥ beats a lone 6♥")
    }

    func testOtherSuitBeatsEmptyColumnEvenToTheLeft() {
        var t = Table()
        let state = t.state([[t.c(.six, .clubs)], [t.c(.two, up: false), t.c(.five, .hearts)], []], pad: false)
        XCTAssertEqual(state.bestDestination(from: 1, index: 1), 0)
    }

    func testFaceDownCardHasNoDestination() {
        var t = Table()
        let state = t.state([[t.c(.five, .hearts, up: false), t.c(.king)], [t.c(.six, .hearts)]])
        XCTAssertNil(state.bestDestination(from: 0, index: 0))
    }

    func testRunMovesTogetherAndUndoes() throws {
        var t = Table()
        let run = t.run(.nine, .seven, .hearts)
        var game = SpiderGame(
            state: t.state([[t.c(.two, up: false)] + run, [t.c(.ten, .clubs)], [t.c(.ten, .hearts)]]))
        let to = try XCTUnwrap(game.state.bestDestination(from: 0, index: 1))
        XCTAssertEqual(to, 2)
        try game.perform(.move(from: 0, index: 1, to: to))
        XCTAssertEqual(Array(game.state.columns[2].dropFirst()).map(\.id), run.map(\.id))
        XCTAssertTrue(game.state.columns[0][0].isFaceUp, "the uncovered card turns over")
        try game.undo()
        XCTAssertEqual(Array(game.state.columns[0].dropFirst()).map(\.id), run.map(\.id))
        XCTAssertEqual(game.state.columns[2].count, 1)
    }
}
