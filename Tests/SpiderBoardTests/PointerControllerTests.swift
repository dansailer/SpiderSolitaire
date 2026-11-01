import SpiderCore
import XCTest

@testable import SpiderBoard

final class PointerControllerTests: XCTestCase {
    let layout = BoardLayout(boardSize: BoardSize(width: 800, height: 600))

    private func center(_ state: GameState, _ column: Int, _ index: Int) -> BoardPoint {
        let f = layout.cardFrames(column: column, cards: state.columns[column])[index]
        return BoardPoint(x: f.midX, y: f.minY + 2) // the strip of a card that stays visible
    }

    private func translation(from: BoardPoint, toColumn column: Int, in state: GameState) -> BoardSize {
        let target =
            layout.cardFrames(column: column, cards: state.columns[column]).last ?? layout.slotFrame(column: column)
        return BoardSize(width: target.midX - from.x, height: target.midY - from.y)
    }

    private func drag(_ p: inout PointerController, start: BoardPoint, to t: BoardSize, state: GameState)
        -> PointerController.Result
    {
        p.pointerChanged(
            start: start, translation: BoardSize(width: t.width / 2, height: t.height / 2), state: state, layout: layout
        )
        p.pointerChanged(start: start, translation: t, state: state, layout: layout)
        return p.pointerEnded(start: start, translation: t, time: 0, state: state, layout: layout)
    }

    func testDragRunFromMiddleOfSameSuitRun() {
        var k = Cards()
        let state = k.state([
            [k.c(.two, up: false), k.c(.nine, .hearts), k.c(.eight, .hearts), k.c(.seven, .hearts)],
            [k.c(.nine, .clubs)],
        ])
        var p = PointerController()
        let start = center(state, 0, 2)
        let t = translation(from: start, toColumn: 1, in: state)
        p.pointerChanged(start: start, translation: BoardSize(width: 10, height: 0), state: state, layout: layout)
        XCTAssertEqual(p.drag?.from, 0)
        XCTAssertEqual(p.drag?.index, 2)
        XCTAssertTrue(p.isDragging(column: 0, index: 3))
        XCTAssertFalse(p.isDragging(column: 0, index: 1))
        p.pointerChanged(start: start, translation: t, state: state, layout: layout)
        XCTAssertEqual(p.drag?.translation, t)
        let result = p.pointerEnded(start: start, translation: t, time: 0, state: state, layout: layout)
        XCTAssertEqual(result, .perform(.move(from: 0, index: 2, to: 1)))
        XCTAssertNil(p.drag)
    }

    func testIllegalDropSnapsBack() {
        var k = Cards()
        let state = k.state([[k.c(.five, .hearts)], [k.c(.nine)]])
        var p = PointerController()
        let start = center(state, 0, 0)
        XCTAssertEqual(
            drag(&p, start: start, to: translation(from: start, toColumn: 1, in: state), state: state), .snapBack)
        XCTAssertNil(p.drag)
    }

    func testCannotDragMixedSuitStackOrFaceDownCard() {
        var k = Cards()
        let state = k.state([[k.c(.three, up: false), k.c(.seven, .hearts), k.c(.six)], [k.c(.eight)]])
        var p = PointerController()
        let start = center(state, 0, 1)
        let result = drag(&p, start: start, to: translation(from: start, toColumn: 1, in: state), state: state)
        XCTAssertEqual(result, .none)
        let down = center(state, 0, 0)
        XCTAssertEqual(drag(&p, start: down, to: BoardSize(width: 100, height: 0), state: state), .none)
    }

    func testTinyMovementIsAClickNotADrag() {
        var k = Cards()
        let state = k.state([[k.c(.five, .hearts)], [k.c(.six, .hearts)]])
        var p = PointerController()
        let start = center(state, 0, 0)
        p.pointerChanged(start: start, translation: BoardSize(width: 1, height: 1), state: state, layout: layout)
        XCTAssertNil(p.drag)
        XCTAssertEqual(
            p.pointerEnded(
                start: start, translation: BoardSize(width: 1, height: 1), time: 1, state: state, layout: layout),
            .perform(.move(from: 0, index: 0, to: 1)), "a click moves the card")
    }

    func testSingleClickAutoMovesToBestTarget() {
        var k = Cards()
        let state = k.state([[k.c(.five, .hearts)], [k.c(.six, .clubs)], [k.c(.six, .hearts)]])
        var p = PointerController()
        let start = center(state, 0, 0)
        p.pointerChanged(start: start, translation: .zero, state: state, layout: layout)
        XCTAssertNil(p.drag, "a press alone lifts nothing")
        XCTAssertEqual(
            p.pointerEnded(start: start, translation: .zero, time: 10, state: state, layout: layout),
            .perform(.move(from: 0, index: 0, to: 2)))
    }

    func testClickMovesTheRunOnTopOfTheCard() {
        var k = Cards()
        let state = k.state([
            [k.c(.two, up: false), k.c(.nine, .hearts), k.c(.eight, .hearts), k.c(.seven, .hearts)],
            [k.c(.nine, .clubs)],
        ])
        var p = PointerController()
        XCTAssertEqual(
            p.pointerEnded(start: center(state, 0, 2), translation: .zero, time: 0, state: state, layout: layout),
            .perform(.move(from: 0, index: 2, to: 1)))
    }

    func testClickWithNowhereToGoOrOnAnUnmovableCardDoesNothing() {
        var k = Cards()
        // No empty columns, so the jack has nowhere to go.
        let kings = (3..<GameState.columnCount).map { _ in [k.c(.king)] }
        let state = k.state(
            [[k.c(.seven, .hearts), k.c(.six)], [k.c(.eight)], [k.c(.three, up: false), k.c(.jack)]] + kings)
        var p = PointerController()
        XCTAssertEqual(
            p.pointerEnded(start: center(state, 0, 0), translation: .zero, time: 0, state: state, layout: layout),
            .none, "mixed suits can't be lifted")
        XCTAssertEqual(
            p.pointerEnded(start: center(state, 2, 0), translation: .zero, time: 1, state: state, layout: layout),
            .none, "face-down card")
        XCTAssertEqual(
            p.pointerEnded(start: center(state, 2, 1), translation: .zero, time: 2, state: state, layout: layout),
            .none, "no target")
    }

    func testDoubleClickMovesOnlyOnce() throws {
        var k = Cards()
        var game = SpiderGame(
            state: k.state([
                [k.c(.seven, .clubs), k.c(.five, .hearts)], [k.c(.eight, .diamonds)], [k.c(.six, .hearts)],
            ]))
        var p = PointerController()
        let spot = center(game.state, 0, 1)
        let first = p.pointerEnded(start: spot, translation: .zero, time: 10, state: game.state, layout: layout)
        XCTAssertEqual(first, .perform(.move(from: 0, index: 1, to: 2)))
        try game.perform(.move(from: 0, index: 1, to: 2))
        // The 7♣ is now under the pointer and could go on the 8♦, but the second click of the
        // double-click (and a third one right after) must not move it.
        XCTAssertEqual(game.state.bestDestination(from: 0, index: 0), 1)
        XCTAssertTrue(p.continuesDoubleClick(start: spot, translation: .zero, time: 10.2))
        XCTAssertFalse(
            p.continuesDoubleClick(start: spot, translation: BoardSize(width: 10, height: 0), time: 10.2),
            "a drag is not a click")
        XCTAssertEqual(
            p.pointerEnded(start: spot, translation: .zero, time: 10.2, state: game.state, layout: layout), .none)
        XCTAssertEqual(
            p.pointerEnded(
                start: BoardPoint(x: spot.x + 2, y: spot.y + 1), translation: .zero, time: 10.3, state: game.state,
                layout: layout), .none)
        // A later click is a new click.
        XCTAssertEqual(
            p.pointerEnded(start: spot, translation: .zero, time: 11, state: game.state, layout: layout),
            .perform(.move(from: 0, index: 0, to: 1)))
    }

    func testQuickClicksOnOtherCardsOrTheStockStillAct() {
        var k = Cards()
        let state = k.state(
            [[k.c(.five, .hearts)], [k.c(.six, .hearts)], [k.c(.four, .clubs)], [k.c(.king)]]
                + (4..<10).map { _ in
                    [k.c(.king)]
                }, stock: 10)
        var p = PointerController()
        _ = p.pointerEnded(start: center(state, 0, 0), translation: .zero, time: 0, state: state, layout: layout)
        XCTAssertEqual(
            p.pointerEnded(start: center(state, 2, 0), translation: .zero, time: 0.1, state: state, layout: layout),
            .perform(.move(from: 2, index: 0, to: 0)), "other card")
        let stock = layout.stockFrames(dealsRemaining: 1)[0]
        XCTAssertEqual(
            p.pointerEnded(start: stock.center, translation: .zero, time: 0.15, state: state, layout: layout),
            .perform(.deal))
        XCTAssertEqual(
            p.pointerEnded(start: stock.center, translation: .zero, time: 0.2, state: state, layout: layout),
            .perform(.deal), "the stock deals on every click")
    }

    func testDoubleClickIntervalFollowsTheSetting() {
        var k = Cards()
        let state = k.state([[k.c(.five, .hearts)], [k.c(.six, .clubs)], [k.c(.six, .hearts)]])
        var p = PointerController()
        p.doubleClickInterval = 0.1
        let start = center(state, 0, 0)
        _ = p.pointerEnded(start: start, translation: .zero, time: 0, state: state, layout: layout)
        XCTAssertEqual(
            p.pointerEnded(start: start, translation: .zero, time: 0.2, state: state, layout: layout),
            .perform(.move(from: 0, index: 0, to: 2)))
    }

    func testClickOnStockDeals() {
        var k = Cards()
        let state = k.state((0..<10).map { _ in [k.c(.king)] }, stock: 20)
        var p = PointerController()
        let stock = layout.stockFrames(dealsRemaining: 2).last!
        XCTAssertEqual(
            p.pointerEnded(start: stock.center, translation: .zero, time: 0, state: state, layout: layout),
            .perform(.deal))
        let felt = BoardPoint(x: layout.scoreBoxFrame.midX, y: layout.tableauBottom - 2)
        XCTAssertEqual(p.pointerEnded(start: felt, translation: .zero, time: 0, state: state, layout: layout), .none)
    }

    func testDealResultEvenWhenBlockedLetsEngineDecide() {
        // The controller reports the click; SpiderGame refuses the deal (empty column) and the UI shows why.
        var k = Cards()
        let state = k.state([(0..<12).map { _ in k.c(.king, up: false) } + [k.c(.king)]], stock: 10)
        var p = PointerController()
        let stock = layout.stockFrames(dealsRemaining: 1)[0]
        XCTAssertEqual(
            p.pointerEnded(start: stock.center, translation: .zero, time: 0, state: state, layout: layout),
            .perform(.deal))
        XCTAssertFalse(state.canDeal)
    }

    func testFullGameDragsMatchEngine() throws {
        // Play hints through the pointer layer only: every hinted move must be reachable by a drag.
        var game = SpiderGame(difficulty: .twoSuits, seed: 12)
        var p = PointerController()
        for _ in 0..<40 {
            guard let hint = game.state.hints().first else {
                if game.state.canDeal { try game.perform(.deal); continue } else { break }
            }
            let start = center(game.state, hint.from, hint.index)
            let t = translation(from: start, toColumn: hint.to, in: game.state)
            let result = drag(&p, start: start, to: t, state: game.state)
            XCTAssertEqual(result, .perform(hint.action))
            try game.perform(hint.action)
        }
    }
}

final class PointerControllerRecoveryTests: XCTestCase {
    func testNewPressAfterCancelledGestureStartsFresh() {
        var k = Cards()
        let layout = BoardLayout(boardSize: BoardSize(width: 800, height: 600))
        let state = k.state([[k.c(.five, .hearts)], [k.c(.six, .hearts)], [k.c(.nine, .clubs)]])
        var p = PointerController()
        let a = layout.cardFrames(column: 0, cards: state.columns[0])[0].center
        p.pointerChanged(start: a, translation: BoardSize(width: 40, height: 0), state: state, layout: layout)
        XCTAssertEqual(p.drag?.from, 0)
        // No end event (e.g. an alert stole the mouse). The next gesture starts on column 2.
        let b = layout.cardFrames(column: 2, cards: state.columns[2])[0].center
        p.pointerChanged(start: b, translation: BoardSize(width: 40, height: 0), state: state, layout: layout)
        XCTAssertEqual(p.drag?.from, 2)
    }
}
