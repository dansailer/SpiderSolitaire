import SpiderCore
import XCTest

@testable import SpiderBoard

/// The deal pacing the player sees: each card visibly flies on its own, and the totals stay in
/// the agreed window (stock deal about 1 s, new game about 2.5–3.5 s).
final class DealPacingTests: XCTestCase {
    func testStockDealTakesAboutOneSecond() {
        let total = DealPacing.totalDuration(.stock, cards: GameState.columnCount)
        XCTAssertEqual(total, 9 * 0.08 + 0.24, accuracy: 1e-9)
        XCTAssertTrue((0.8...1.2).contains(total), "\(total)")
    }

    func testNewGameDealTakesAboutThreeSeconds() {
        let game = SpiderGame(difficulty: .oneSuit, seed: 1)
        XCTAssertEqual(game.state.tableauCardCount, 54)
        let total = DealPacing.totalDuration(.initial, cards: 54)
        XCTAssertEqual(total, 0.15 + 53 * 0.05 + 0.24, accuracy: 1e-9)
        XCTAssertTrue((2.5...3.5).contains(total), "\(total)")
    }

    /// Cards follow each other closely enough to read as one deal, yet several are never
    /// launched within one flight's first third, so every landing can be followed.
    func testEveryCardIsSeenOnItsOwn() {
        for kind in [DealPacing.Kind.initial, .stock] {
            let stagger = DealPacing.stagger(kind)
            XCTAssertGreaterThanOrEqual(stagger, 0.05, "\(kind)")
            XCTAssertLessThanOrEqual(stagger, 0.08, "\(kind)")
            XCTAssertGreaterThan(stagger, DealPacing.flightDuration / 5, "\(kind)")
        }
        XCTAssertTrue((0.2...0.25).contains(DealPacing.flightDuration))
    }

    func testReleaseTimesAreEvenlySpacedAfterTheLeadIn() {
        XCTAssertEqual(DealPacing.releaseTime(.stock, index: 0), 0)
        XCTAssertEqual(DealPacing.releaseTime(.stock, index: 3), 0.24, accuracy: 1e-9)
        XCTAssertEqual(DealPacing.releaseTime(.initial, index: 0), DealPacing.initialLeadIn)
        XCTAssertEqual(DealPacing.releaseTime(.initial, index: 10), DealPacing.initialLeadIn + 0.5, accuracy: 1e-9)
        XCTAssertEqual(DealPacing.releaseTime(.stock, index: -2), 0)
        XCTAssertEqual(DealPacing.totalDuration(.stock, cards: 0), 0)
    }

    func testSoundPlaysPerStockCardAndPerRowOfTheNewGameDeal() {
        XCTAssertEqual((0..<10).filter { DealPacing.playsSound(.stock, index: $0) }.count, 10)
        XCTAssertEqual((0..<54).filter { DealPacing.playsSound(.initial, index: $0) }, [0, 10, 20, 30, 40, 50])
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
        XCTAssertFalse(anim.isDealing)
        XCTAssertTrue(anim.isIdle)
        XCTAssertEqual(layout.placements(for: game.state, animations: anim), layout.placements(for: game.state))
    }
}
