import SpiderCore
import XCTest

@testable import SpiderBoard

/// A card on its way somewhere is drawn above every column for the whole trip. SwiftUI applies a
/// new `zIndex` at once, so a card raised only to its destination's column order would pass
/// behind taller columns on the way (reported for the stock deal).
final class ZOrderTests: XCTestCase {
    let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 700))

    private func z(_ placements: [CardPlacement]) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0.zIndex) })
    }

    func testCardsDealtFromTheStockFlyAboveEveryColumn() throws {
        var game = SpiderGame(difficulty: .fourSuits, seed: 9)
        let dealsBefore = game.state.dealsRemaining
        let outcome = try game.perform(.deal)
        var anim = BoardAnimations()
        anim.beginDeal(outcome, dealsBefore: dealsBefore)
        let dealt = outcome.dealtCardIDs
        var inAir: [Int] = []
        for id in dealt {
            anim.releaseDealtCard(id)
            inAir.append(id)
            let zs = z(layout.placements(for: game.state, animations: anim))
            let lowestInAir = inAir.map { zs[$0]! }.min()!
            let highestOther = zs.filter { !inAir.contains($0.key) }.map(\.value).max()!
            XCTAssertGreaterThan(lowestInAir, highestOther, "card \(id) passes over the columns")
            // The card just dealt (next column) flies over the ones dealt before it.
            XCTAssertEqual(zs[id], inAir.map { zs[$0]! }.max())
        }
        for id in dealt { anim.landDealtCard(id) }
        XCTAssertEqual(layout.placements(for: game.state, animations: anim), layout.placements(for: game.state))
    }

    func testANewGameDealFliesAboveTheCardsAlreadyDealt() {
        let game = SpiderGame(difficulty: .oneSuit, seed: 4)
        var anim = BoardAnimations()
        anim.beginInitialDeal(game.state)
        let order = DealPacing.initialDealOrder(game.state.columns)
        // Rows 1–4 landed, the first three cards of row 5 in the air.
        for id in order.prefix(43) { anim.releaseDealtCard(id) }
        for id in order.prefix(40) { anim.landDealtCard(id) }
        let zs = z(layout.placements(for: game.state, animations: anim))
        let inAir = Array(order[40..<43])
        XCTAssertGreaterThan(inAir.map { zs[$0]! }.min()!, order.prefix(40).map { zs[$0]! }.max()!)
        XCTAssertEqual(inAir.map { zs[$0]! }, inAir.map { zs[$0]! }.sorted(), "later cards on top")
    }

    func testAMovedRunGlidesAboveEveryColumnUntilItsGlideEnds() throws {
        var k = Cards()
        let tall = (0..<12).map { _ in k.c(.three, .hearts, up: false) } + [k.c(.queen, .hearts)]
        let state = k.state([[k.c(.ten)], tall, [k.c(.nine), k.c(.eight)]])
        var game = SpiderGame(state: state)
        let run = Set(state.columns[2].map(\.id))
        try game.perform(.move(from: 2, index: 0, to: 0))
        let moved = BoardAnimations.movedCardIDs(from: state, to: game.state)
        XCTAssertEqual(moved, run)

        var anim = BoardAnimations()
        anim.beginMoves(moved)
        var zs = z(layout.placements(for: game.state, animations: anim))
        let highestOther = zs.filter { !run.contains($0.key) }.map(\.value).max()!
        XCTAssertGreaterThan(run.map { zs[$0]! }.min()!, highestOther, "over the tall column 2")
        let column0 = game.state.columns[0].map { zs[$0.id]! }
        XCTAssertEqual(column0, column0.sorted(), "the run keeps its own order")

        // Dragging another run while the glide ends: the dragged run is still on top.
        let drag = PointerController.Drag(from: 1, index: 12, translation: BoardSize(width: 5, height: 5))
        zs = z(layout.placements(for: game.state, drag: drag, animations: anim))
        XCTAssertGreaterThan(zs[tall.last!.id]!, run.map { zs[$0]! }.max()!)

        anim.endMoves()
        XCTAssertTrue(anim.movingIDs.isEmpty)
        XCTAssertEqual(layout.placements(for: game.state, animations: anim), layout.placements(for: game.state))
    }

    /// Undoing a deal (undo modes that allow it) sends the cards back over the columns to the stock.
    func testUndoingADealGlidesTheCardsBackAboveTheColumns() throws {
        var game = SpiderGame(difficulty: .twoSuits, seed: 2)
        let before = game.state
        let outcome = try game.perform(.deal)
        let moved = BoardAnimations.movedCardIDs(from: game.state, to: before)
        XCTAssertEqual(moved, Set(outcome.dealtCardIDs))

        var anim = BoardAnimations()
        anim.beginMoves(moved)
        let zs = z(layout.placements(for: before, animations: anim))
        let highestOther = zs.filter { !moved.contains($0.key) }.map(\.value).max()!
        XCTAssertGreaterThan(moved.map { zs[$0]! }.min()!, highestOther)
    }

    func testNothingMovesWhenNothingChangedColumn() {
        let state = GameState.newGame(difficulty: .oneSuit, seed: 1)
        XCTAssertTrue(BoardAnimations.movedCardIDs(from: state, to: state).isEmpty)
    }
}
