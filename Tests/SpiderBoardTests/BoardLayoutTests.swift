import XCTest
import SpiderCore
@testable import SpiderBoard

/// Hand-built cards for board tests.
struct Cards {
    private var nextID = 5000
    mutating func c(_ rank: Rank, _ suit: Suit = .spades, up: Bool = true) -> Card {
        nextID += 1
        return Card(id: nextID, suit: suit, rank: rank, isFaceUp: up)
    }
    mutating func state(_ columns: [[Card]], stock: Int = 0) -> GameState {
        var cols = columns
        while cols.count < GameState.columnCount { cols.append([]) }
        let stockCards = (0..<stock).map { _ in c(.two, .clubs, up: false) }
        return GameState(difficulty: .fourSuits, seed: 0, columns: cols, stock: stockCards)
    }
}

final class BoardLayoutTests: XCTestCase {
    let size = Size(width: 800, height: 600)

    func testCardsScaleWithWidthAndKeepAspect() {
        let small = BoardLayout(boardSize: Size(width: 800, height: 600))
        let big = BoardLayout(boardSize: Size(width: 1100, height: 900))
        XCTAssertGreaterThan(big.cardSize.width, small.cardSize.width)
        for layout in [small, big] {
            XCTAssertEqual(layout.cardSize.height / layout.cardSize.width, 96.0 / 71.0, accuracy: 1e-9)
        }
        XCTAssertEqual(small.cardSize.width, 800 / (10 + 11 * BoardLayout.gapRatio), accuracy: 1e-9)
    }

    func testCardWidthClampedAndRowCentred() {
        let huge = BoardLayout(boardSize: Size(width: 4000, height: 3000))
        XCTAssertEqual(huge.cardSize.width, BoardLayout.maxCardWidth)
        let rowWidth = huge.columnX[9] + huge.cardSize.width - huge.columnX[0]
        XCTAssertEqual(huge.columnX[0], (4000 - rowWidth) / 2, accuracy: 1e-9)
        XCTAssertEqual(BoardLayout(boardSize: Size(width: 100, height: 100)).cardSize.width, BoardLayout.minCardWidth)
    }

    func testShortWindowLimitsCardSizeByHeight() {
        let wideShort = BoardLayout(boardSize: Size(width: 1600, height: 500))
        XCTAssertLessThanOrEqual(wideShort.cardSize.height * 2.6, 500 + 1e-9)
    }

    func testColumnsEvenlySpacedInsideWindow() {
        let layout = BoardLayout(boardSize: size)
        XCTAssertEqual(layout.columnX.count, 10)
        for i in 1..<10 {
            XCTAssertEqual(layout.columnX[i] - layout.columnX[i - 1], layout.cardSize.width + layout.gap, accuracy: 1e-9)
        }
        XCTAssertGreaterThanOrEqual(layout.columnX[0], 0)
        XCTAssertLessThanOrEqual(layout.columnX[9] + layout.cardSize.width, size.width + 1e-9)
    }

    func testFaceDownStepSmallerThanFaceUp() {
        var k = Cards()
        let layout = BoardLayout(boardSize: size)
        let cards = [k.c(.two, up: false), k.c(.three, up: false), k.c(.nine), k.c(.eight), k.c(.seven)]
        let y = layout.cardOffsets(for: cards)
        XCTAssertEqual(y.count, 5)
        XCTAssertEqual(y[0], layout.tableauTop)
        let down = y[1] - y[0], up = y[3] - y[2]
        XCTAssertEqual(down, layout.cardSize.height * BoardLayout.faceDownStepRatio, accuracy: 1e-9)
        XCTAssertEqual(up, layout.cardSize.height * BoardLayout.faceUpStepRatio, accuracy: 1e-9)
        XCTAssertLessThan(down, up)
        XCTAssertTrue(layout.cardOffsets(for: []).isEmpty)
    }

    func testTallColumnsCompressToFitAboveBottomRow() {
        var k = Cards()
        let layout = BoardLayout(boardSize: size)
        let cards = (0..<10).map { _ in k.c(.two, up: false) } + (0..<20).map { _ in k.c(.five) }
        let y = layout.cardOffsets(for: cards)
        XCTAssertEqual(y.last! + layout.cardSize.height, layout.tableauBottom, accuracy: 1e-6)
        XCTAssertLessThan(layout.tableauBottom, layout.bottomRowY)
        for i in 1..<y.count { XCTAssertGreaterThan(y[i], y[i - 1], "still fanned, just tighter") }
        // Proportions kept: face-down steps stay smaller than face-up steps.
        XCTAssertLessThan(y[1] - y[0], y[12] - y[11])
    }

    func testBottomRowPlacement() {
        let layout = BoardLayout(boardSize: size)
        XCTAssertEqual(layout.bottomRowY + layout.cardSize.height + layout.gap, size.height, accuracy: 1e-9)

        let stock = layout.stockFrames(dealsRemaining: 5)
        XCTAssertEqual(stock.count, 5)
        XCTAssertEqual(stock.last!.maxX, layout.columnX[9] + layout.cardSize.width, accuracy: 1e-9, "right-aligned")
        XCTAssertTrue(zip(stock, stock.dropFirst()).allSatisfy { $0.x < $1.x }, "top of pile rightmost")
        XCTAssertTrue(layout.stockFrames(dealsRemaining: 0).isEmpty)
        XCTAssertNil(layout.stockHitFrame(dealsRemaining: 0))

        let foundation = layout.foundationFrames(count: 3)
        XCTAssertEqual(foundation.first!.x, layout.columnX[0])
        XCTAssertTrue(layout.foundationAreaFrame.maxX >= foundation.last!.maxX)

        let score = layout.scoreBoxFrame
        XCTAssertEqual(score.midX, size.width / 2, accuracy: 1e-9)
        XCTAssertEqual(score.midY, layout.bottomRowY + layout.cardSize.height / 2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(layout.foundationAreaFrame.maxX, score.minX, "no overlap with foundation")
        XCTAssertLessThanOrEqual(score.maxX, stock.first!.minX, "no overlap with stock")
    }

    func testStockIndexMapsToDealGroup() {
        let layout = BoardLayout(boardSize: size)
        let frames = layout.stockFrames(dealsRemaining: 3)
        XCTAssertEqual(layout.stockFrame(forStockIndex: 29, dealsRemaining: 3), frames[2], "next dealt is on top")
        XCTAssertEqual(layout.stockFrame(forStockIndex: 0, dealsRemaining: 3), frames[0])
        XCTAssertNil(layout.stockFrame(forStockIndex: 30, dealsRemaining: 3))
    }

    func testHitTestingFindsTopmostCard() {
        var k = Cards()
        let state = k.state([[k.c(.two, up: false), k.c(.nine), k.c(.eight)]])
        let layout = BoardLayout(boardSize: size)
        let f = layout.cardFrames(column: 0, cards: state.columns[0])
        XCTAssertEqual(layout.card(at: Point(x: f[0].midX, y: f[0].minY + 1), in: state), CardLocation(column: 0, index: 0))
        XCTAssertEqual(layout.card(at: Point(x: f[1].midX, y: f[1].minY + 1), in: state), CardLocation(column: 0, index: 1))
        XCTAssertEqual(layout.card(at: f[2].center, in: state), CardLocation(column: 0, index: 2))
        XCTAssertNil(layout.card(at: Point(x: f[0].midX, y: f[2].maxY + 5), in: state), "below the column")
        XCTAssertNil(layout.card(at: Point(x: layout.columnX[1] - layout.gap / 2, y: f[0].midY), in: state), "in the gap")
        XCTAssertNil(layout.card(at: layout.slotFrame(column: 4).center, in: state), "empty column")
    }

    func testDropPicksLegalColumnWithMostOverlap() {
        var k = Cards()
        let state = k.state([
            [k.c(.five, .hearts)],
            [k.c(.six, .clubs)],
            [k.c(.six, .hearts)],
            [k.c(.nine)],
        ])
        let layout = BoardLayout(boardSize: size)
        let source = layout.cardFrames(column: 0, cards: state.columns[0])[0]
        let target1 = layout.cardFrames(column: 1, cards: state.columns[1])[0]
        let target3 = layout.cardFrames(column: 3, cards: state.columns[3])[0]

        // Mostly over column 1, a little over column 2.
        let dx1 = target1.x - source.x + layout.cardSize.width * 0.3
        XCTAssertEqual(layout.dropColumn(for: state, from: 0, index: 0, draggedFrame: source.offsetBy(dx: dx1, dy: 20)), 1)
        // Dead centre on column 2.
        let dx2 = layout.columnX[2] - source.x
        XCTAssertEqual(layout.dropColumn(for: state, from: 0, index: 0, draggedFrame: source.offsetBy(dx: dx2, dy: 10)), 2)
        // Over the illegal 9: nothing.
        XCTAssertNil(layout.dropColumn(for: state, from: 0, index: 0, draggedFrame: source.offsetBy(dx: target3.x - source.x, dy: 0)))
        // Over an empty column's slot: allowed.
        let dx5 = layout.columnX[5] - source.x
        XCTAssertEqual(layout.dropColumn(for: state, from: 0, index: 0, draggedFrame: source.offsetBy(dx: dx5, dy: 0)), 5)
        // Dropped back on itself / far away: nothing.
        XCTAssertNil(layout.dropColumn(for: state, from: 0, index: 0, draggedFrame: source))
        XCTAssertNil(layout.dropColumn(for: state, from: 0, index: 0, draggedFrame: source.offsetBy(dx: 0, dy: 400)))
    }

    func testRectHelpers() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(a.intersectionArea(Rect(x: 5, y: 5, width: 10, height: 10)), 25)
        XCTAssertEqual(a.intersectionArea(Rect(x: 10, y: 0, width: 5, height: 5)), 0)
        XCTAssertEqual(a.union(Rect(x: 20, y: 5, width: 5, height: 10)), Rect(x: 0, y: 0, width: 25, height: 15))
        XCTAssertTrue(a.contains(Point(x: 0, y: 0)))
        XCTAssertFalse(a.contains(Point(x: 10, y: 5)))
    }
}
