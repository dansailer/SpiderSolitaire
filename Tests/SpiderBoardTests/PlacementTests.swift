import SpiderCore
import XCTest

@testable import SpiderBoard

final class PlacementTests: XCTestCase {
    let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 700))

    func testEveryStockAndTableauCardPlacedOnceWithStableIDs() {
        let state = GameState.newGame(difficulty: .fourSuits, seed: 3)
        let placements = layout.placements(for: state)
        XCTAssertEqual(placements.count, 104)
        XCTAssertEqual(Set(placements.map(\.id)).count, 104)
        let stock = placements.filter { !$0.card.isFaceUp && $0.frame.minY == layout.bottomRowY }
        XCTAssertEqual(stock.count, 50)
        XCTAssertTrue(placements.allSatisfy { !$0.isLifted })
    }

    func testStacksDrawInOrder() {
        let state = GameState.newGame(difficulty: .oneSuit, seed: 1)
        let placements = layout.placements(for: state)
        let column0 = placements.filter { state.columns[0].map(\.id).contains($0.id) }
        XCTAssertEqual(column0.map(\.zIndex), column0.map(\.zIndex).sorted())
        let maxStock = placements.filter { state.stock.map(\.id).contains($0.id) }.map(\.zIndex).max()!
        XCTAssertLessThan(maxStock, column0.map(\.zIndex).min()!)
    }

    func testDraggedRunIsTranslatedAndOnTop() {
        var k = Cards()
        let state = k.state([[k.c(.two, up: false), k.c(.nine), k.c(.eight)], [k.c(.king)]])
        let drag = PointerController.Drag(from: 0, index: 1, translation: BoardSize(width: 30, height: -10))
        let placements = layout.placements(for: state, drag: drag)
        let frames = layout.cardFrames(column: 0, cards: state.columns[0])
        let p = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        let ids = state.columns[0].map(\.id)
        XCTAssertFalse(p[ids[0]]!.isLifted)
        XCTAssertEqual(p[ids[0]]!.frame, frames[0])
        XCTAssertTrue(p[ids[1]]!.isLifted)
        XCTAssertEqual(p[ids[2]]!.frame, frames[2].offsetBy(dx: 30, dy: -10))
        XCTAssertGreaterThan(p[ids[1]]!.zIndex, p[state.columns[1][0].id]!.zIndex)
    }

    func testPipCountsMatchRank() {
        for rank in Rank.allCases {
            let pips = CardFace.pips(for: rank)
            XCTAssertEqual(pips.count, CardFace.isCourt(rank) ? 0 : rank.rawValue, "\(rank)")
            XCTAssertEqual(Set(pips).count, pips.count, "no overlapping pips for \(rank)")
            XCTAssertTrue(pips.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        }
        XCTAssertTrue(CardFace.pips(for: .two)[1].inverted)
        XCTAssertFalse(CardFace.pips(for: .two)[0].inverted)
    }
}
