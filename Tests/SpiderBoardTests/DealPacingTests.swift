import SpiderCore
import XCTest

@testable import SpiderBoard

/// The deal pacing the player sees: XP deals about 8–10 cards a second, so every card is seen
/// being placed. The totals stay in the agreed window (stock deal about 1.2 s, new game about 6.4 s).
final class DealPacingTests: XCTestCase {
    func testStockDealTakesAboutOneSecond() {
        let total = DealPacing.totalDuration(.stock, cards: GameState.columnCount)
        XCTAssertEqual(total, 9 * 0.1 + 0.3, accuracy: 1e-9)
        XCTAssertTrue((1.0...1.5).contains(total), "\(total)")
    }

    func testNewGameDealTakesAboutSixSeconds() {
        let game = SpiderGame(difficulty: .oneSuit, seed: 1)
        XCTAssertEqual(game.state.tableauCardCount, 54)
        let total = DealPacing.totalDuration(.initial, cards: 54)
        XCTAssertEqual(total, 0.3 + 53 * 0.11 + 0.3, accuracy: 1e-9)
        XCTAssertTrue((5.5...7.0).contains(total), "\(total)")
    }

    /// 8–10 cards a second, like XP: slow enough to follow each card, and at most a few in the
    /// air at once.
    func testEveryCardIsSeenOnItsOwn() {
        for kind in [DealPacing.Kind.initial, .stock] {
            let cardsPerSecond = 1 / DealPacing.stagger(kind)
            XCTAssertTrue((8.0...10.0).contains(cardsPerSecond), "\(kind): \(cardsPerSecond)")
            XCTAssertGreaterThan(DealPacing.stagger(kind), DealPacing.flightDuration / 4, "\(kind)")
        }
        XCTAssertTrue((0.25...0.35).contains(DealPacing.flightDuration))
    }

    func testReleaseTimesAreEvenlySpacedAfterTheLeadIn() {
        XCTAssertEqual(DealPacing.releaseTime(.stock, index: 0), 0)
        XCTAssertEqual(DealPacing.releaseTime(.stock, index: 3), 0.3, accuracy: 1e-9)
        XCTAssertEqual(DealPacing.releaseTime(.initial, index: 0), DealPacing.initialLeadIn)
        XCTAssertEqual(DealPacing.releaseTime(.initial, index: 10), DealPacing.initialLeadIn + 1.1, accuracy: 1e-9)
        XCTAssertEqual(DealPacing.releaseTime(.stock, index: -2), 0)
        XCTAssertEqual(DealPacing.totalDuration(.stock, cards: 0), 0)
    }

    /// Like dealing by hand: across the row, then the next row; columns 1–4 get the sixth card.
    func testNewGameDealsRowByRow() {
        let game = SpiderGame(difficulty: .fourSuits, seed: 7)
        let columns = game.state.columns
        let order = DealPacing.initialDealOrder(columns)
        XCTAssertEqual(order.count, 54)
        XCTAssertEqual(Set(order).count, 54)
        XCTAssertEqual(Array(order.prefix(10)), columns.map { $0[0].id })
        XCTAssertEqual(Array(order[50..<54]), (0..<4).map { columns[$0][5].id })
        XCTAssertEqual(order.last, columns[3].last?.id)
    }

    func testInitialDealHoldsEveryTableauCardOnTheStockThenReleasesThem() {
        let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 700))
        let game = SpiderGame(difficulty: .twoSuits, seed: 3)
        var anim = BoardAnimations()
        anim.beginInitialDeal(game.state)
        XCTAssertTrue(anim.isDealing)
        let order = DealPacing.initialDealOrder(game.state.columns)
        XCTAssertEqual(anim.dealHold?.waitingIDs, order)

        let pile = layout.stockFrames(dealsRemaining: game.state.dealsRemaining).last!
        var byID = Dictionary(
            uniqueKeysWithValues: layout.placements(for: game.state, animations: anim).map { ($0.id, $0) })
        XCTAssertEqual(byID.count, 104)
        for id in order {
            XCTAssertEqual(byID[id]!.frame, pile)
            XCTAssertFalse(byID[id]!.card.isFaceUp)
        }
        // The first card to go is drawn on top of the waiting stack.
        XCTAssertGreaterThan(byID[order[0]]!.zIndex, byID[order[1]]!.zIndex)

        XCTAssertTrue(anim.releaseDealtCard(order[0]))
        byID = Dictionary(
            uniqueKeysWithValues: layout.placements(for: game.state, animations: anim).map { ($0.id, $0) })
        XCTAssertEqual(byID[order[0]]!.frame, layout.cardFrames(in: game.state)[0][0])

        for id in order.dropFirst() { anim.releaseDealtCard(id) }
        XCTAssertTrue(anim.isDealing, "the last card is still in the air")
        for id in order.dropLast() { anim.landDealtCard(id) }
        XCTAssertTrue(anim.isDealing)
        anim.landDealtCard(order.last!)
        XCTAssertFalse(anim.isDealing)
        XCTAssertTrue(anim.isIdle)
        XCTAssertEqual(layout.placements(for: game.state, animations: anim), layout.placements(for: game.state))
    }

    /// XP: every card leaves the stock face down, the top card of each column too, flies to its
    /// column like the others and only turns face up once it has landed. (Drawn face up in flight,
    /// SwiftUI swapped its back for a new face view that faded in at the column instead.)
    func testTheTopCardOfEachColumnFliesFaceDownAndTurnsOverWhenItLands() {
        let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 700))
        let game = SpiderGame(difficulty: .oneSuit, seed: 5)
        let tops = game.state.columns.map { $0.last! }
        XCTAssertEqual(tops.count, 10)
        XCTAssertTrue(tops.allSatisfy(\.isFaceUp))
        var anim = BoardAnimations()
        anim.beginInitialDeal(game.state)
        let order = DealPacing.initialDealOrder(game.state.columns)
        XCTAssertEqual(Set(order).intersection(tops.map(\.id)).count, 10, "the top cards are dealt too")
        func placement(_ id: Int) -> CardPlacement {
            layout.placements(for: game.state, animations: anim).first { $0.id == id }!
        }
        let pile = layout.stockFrames(dealsRemaining: game.state.dealsRemaining).last!
        let frames = layout.cardFrames(in: game.state)
        for top in tops {
            XCTAssertEqual(placement(top.id).frame, pile, "waits on the stock")
            XCTAssertFalse(placement(top.id).card.isFaceUp)
        }
        // In deal order: columns 5–10 get their top card in row 5, columns 1–4 in row 6.
        let columnsInDealOrder = tops.indices.sorted {
            order.firstIndex(of: tops[$0].id)! < order.firstIndex(of: tops[$1].id)!
        }
        for column in columnsInDealOrder {
            let top = tops[column]
            XCTAssertEqual(placement(top.id).frame, pile, "still on the stock until its turn")
            for id in order.prefix(through: order.firstIndex(of: top.id)!) { anim.releaseDealtCard(id) }
            XCTAssertEqual(placement(top.id).frame, frames[column].last!, "flies to its column")
            XCTAssertFalse(placement(top.id).card.isFaceUp, "face down in the air")
            XCTAssertTrue(anim.landDealtCard(top.id))
            XCTAssertTrue(placement(top.id).card.isFaceUp, "turned over on landing")
            XCTAssertEqual(placement(top.id).frame, frames[column].last!)
        }
    }

    /// Each card lands one flight after it leaves; the deal ends when the last one lands.
    func testEveryCardHasAStepFromReleaseToLanding() {
        for (kind, count) in [(DealPacing.Kind.stock, 10), (.initial, 54)] {
            let ids = Array(100..<(100 + count))
            let steps = DealPacing.steps(kind, ids: ids, delay: 0.35)
            XCTAssertEqual(steps.map(\.id), ids)
            for (i, step) in steps.enumerated() {
                XCTAssertEqual(step.release, 0.35 + DealPacing.releaseTime(kind, index: i), accuracy: 1e-9)
                XCTAssertEqual(step.landing, step.release + DealPacing.flightDuration, accuracy: 1e-9)
            }
            XCTAssertEqual(steps.last!.landing, 0.35 + DealPacing.totalDuration(kind, cards: count), accuracy: 1e-9)
        }
        XCTAssertTrue(DealPacing.steps(.stock, ids: []).isEmpty)
    }

    /// A new deal starts clean, even if the previous one was cut short mid-flight.
    func testANewDealForgetsCardsStillInTheAirFromTheLastOne() {
        let game = SpiderGame(difficulty: .oneSuit, seed: 2)
        var anim = BoardAnimations()
        anim.beginInitialDeal(game.state)
        let order = DealPacing.initialDealOrder(game.state.columns)
        for id in order { anim.releaseDealtCard(id) }
        XCTAssertTrue(anim.isDealing)
        anim.beginInitialDeal(game.state)
        XCTAssertTrue(anim.landingDealtIDs.isEmpty)
        XCTAssertEqual(anim.dealHold?.waitingIDs, order)
    }
}

/// The click that skips a deal must not act, and must not swallow the next gesture either.
final class GestureSuppressionTests: XCTestCase {
    let a = BoardPoint(x: 10, y: 20)
    let b = BoardPoint(x: 300, y: 40)

    func testTheSkippingGestureIsIgnoredUntilItEnds() {
        var s = GestureSuppression()
        XCTAssertFalse(s.ignoresChange(start: a))
        s.suppress(start: a)
        XCTAssertTrue(s.ignoresChange(start: a))
        XCTAssertTrue(s.ignoresChange(start: a))
        XCTAssertTrue(s.ignoresEnd(start: a))
        XCTAssertNil(s.start)
        XCTAssertFalse(s.ignoresChange(start: a), "the next click at the same spot acts")
        XCTAssertFalse(s.ignoresEnd(start: a))
    }

    /// The skipping gesture was cancelled without an end event: the next gesture still works.
    func testACancelledSkipDoesNotSwallowTheNextGesture() {
        var s = GestureSuppression()
        s.suppress(start: a)
        XCTAssertFalse(s.ignoresChange(start: b))
        XCTAssertNil(s.start)
        XCTAssertFalse(s.ignoresChange(start: b))
        XCTAssertFalse(s.ignoresEnd(start: b))

        s.suppress(start: a)
        XCTAssertFalse(s.ignoresEnd(start: b), "an end of another gesture is not swallowed")
        XCTAssertNil(s.start)
    }

    func testResetDropsTheSuppression() {
        var s = GestureSuppression()
        s.suppress(start: a)
        s.reset()
        XCTAssertFalse(s.ignoresChange(start: a))
        XCTAssertFalse(s.ignoresEnd(start: a))
    }
}
