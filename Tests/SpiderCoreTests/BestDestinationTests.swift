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
            [t.c(.six, .clubs)],     // 0
            [t.c(.ace)],             // 1
            [t.c(.three)],           // 2
            [t.c(.five, .hearts)],   // 3 source
            [t.c(.nine)],            // 4
            [t.c(.six, .diamonds)],  // 5
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
}
