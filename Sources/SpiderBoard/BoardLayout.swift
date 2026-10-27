import SpiderCore

/// Where everything goes on the felt for a given window size. Pure function of the size (and
/// the cards), so the view just reads frames from here.
public struct BoardLayout: Sendable, Equatable {
    /// Classic Windows card proportions, 71 × 96.
    public static let cardAspect: Double = 96.0 / 71.0
    /// Gap between columns, and outer margins, as a fraction of card width.
    public static let gapRatio: Double = 0.14
    public static let minCardWidth: Double = 40
    public static let maxCardWidth: Double = 120
    /// Vertical fan steps as a fraction of card height (XP: backs tighter than faces).
    public static let faceDownStepRatio: Double = 0.12
    public static let faceUpStepRatio: Double = 0.25
    /// Horizontal step between stacked stock backs / foundation kings, fraction of card width.
    public static let stockStepRatio: Double = 0.16
    public static let foundationStepRatio: Double = 0.22
    /// The board must fit roughly this many card heights vertically (tableau + bottom row).
    static let minHeightInCards: Double = 2.6

    public let boardSize: BoardSize
    public let cardSize: BoardSize
    public let gap: Double
    /// Left edge of each of the 10 columns.
    public let columnX: [Double]
    public let tableauTop: Double
    /// Lowest y a tableau card's bottom edge may reach before columns compress.
    public let tableauBottom: Double
    /// Top edge of the bottom row (foundation, score box, stock).
    public let bottomRowY: Double

    public init(boardSize: BoardSize) {
        self.boardSize = boardSize
        let n = Double(GameState.columnCount)
        let byWidth = boardSize.width / (n + (n + 1) * BoardLayout.gapRatio)
        let byHeight = boardSize.height / (BoardLayout.minHeightInCards * BoardLayout.cardAspect)
        let width = max(BoardLayout.minCardWidth, min(BoardLayout.maxCardWidth, byWidth, byHeight))
        let height = width * BoardLayout.cardAspect
        let gap = width * BoardLayout.gapRatio
        cardSize = BoardSize(width: width, height: height)
        self.gap = gap

        let rowWidth = n * width + (n - 1) * gap
        let left = max(gap, (boardSize.width - rowWidth) / 2)
        columnX = (0..<GameState.columnCount).map { left + Double($0) * (width + gap) }
        tableauTop = gap
        let bottom = max(gap + height + gap, boardSize.height - gap - height)
        bottomRowY = bottom
        tableauBottom = bottom - gap
    }

    // MARK: Tableau

    /// Empty-slot outline for a column.
    public func slotFrame(column: Int) -> BoardRect {
        BoardRect(x: columnX[column], y: tableauTop, width: cardSize.width, height: cardSize.height)
    }

    /// Top edge of each card in a column. Steps shrink proportionally when the natural fan would
    /// run past `tableauBottom`, so tall columns never cover the bottom row.
    public func cardOffsets(for cards: [Card]) -> [Double] {
        guard !cards.isEmpty else { return [] }
        let steps = cards.dropLast().map {
            ($0.isFaceUp ? BoardLayout.faceUpStepRatio : BoardLayout.faceDownStepRatio) * cardSize.height
        }
        let natural = steps.reduce(0, +)
        let available = max(0, tableauBottom - tableauTop - cardSize.height)
        let scale = natural > available && natural > 0 ? available / natural : 1
        var y = tableauTop
        var result: [Double] = [y]
        for step in steps {
            y += step * scale
            result.append(y)
        }
        return result
    }

    public func cardFrames(column: Int, cards: [Card]) -> [BoardRect] {
        cardOffsets(for: cards).map { BoardRect(x: columnX[column], y: $0, width: cardSize.width, height: cardSize.height) }
    }

    public func cardFrames(in state: GameState) -> [[BoardRect]] {
        state.columns.indices.map { cardFrames(column: $0, cards: state.columns[$0]) }
    }

    /// The card under `point`, topmost first (later cards are drawn over earlier ones).
    public func card(at point: BoardPoint, in state: GameState) -> CardLocation? {
        for column in state.columns.indices {
            let x = columnX[column]
            guard point.x >= x, point.x < x + cardSize.width else { continue }
            let frames = cardFrames(column: column, cards: state.columns[column])
            for index in frames.indices.reversed() where frames[index].contains(point) {
                return CardLocation(column: column, index: index)
            }
        }
        return nil
    }

    // MARK: Bottom row

    /// One stacked back per remaining deal, right-aligned with column 10. The last frame is the
    /// top of the pile (the next deal) and sits rightmost.
    public func stockFrames(dealsRemaining: Int) -> [BoardRect] {
        guard dealsRemaining > 0 else { return [] }
        let step = cardSize.width * BoardLayout.stockStepRatio
        let right = columnX[GameState.columnCount - 1]
        return (0..<dealsRemaining).map { i in
            BoardRect(x: right - Double(dealsRemaining - 1 - i) * step, y: bottomRowY,
                 width: cardSize.width, height: cardSize.height)
        }
    }

    /// Frame for the stock card at `stockIndex` in `GameState.stock` (dealt from the end).
    public func stockFrame(forStockIndex stockIndex: Int, dealsRemaining: Int) -> BoardRect? {
        let frames = stockFrames(dealsRemaining: dealsRemaining)
        let group = stockIndex / GameState.columnCount
        return frames.indices.contains(group) ? frames[group] : nil
    }

    public func stockHitFrame(dealsRemaining: Int) -> BoardRect? {
        let frames = stockFrames(dealsRemaining: dealsRemaining)
        guard let first = frames.first, let last = frames.last else { return nil }
        return first.union(last)
    }

    /// One king per completed suit, fanned rightwards from column 1.
    public func foundationFrames(count: Int) -> [BoardRect] {
        let step = cardSize.width * BoardLayout.foundationStepRatio
        return (0..<count).map { i in
            BoardRect(x: columnX[0] + Double(i) * step, y: bottomRowY, width: cardSize.width, height: cardSize.height)
        }
    }

    /// Outline of the empty foundation area (8 fanned cards wide).
    public var foundationAreaFrame: BoardRect {
        let step = cardSize.width * BoardLayout.foundationStepRatio
        return BoardRect(x: columnX[0], y: bottomRowY,
                    width: cardSize.width + Double(GameState.suitsToWin - 1) * step, height: cardSize.height)
    }

    /// XP's centred "Score / Moves" box.
    public var scoreBoxFrame: BoardRect {
        let width = min(cardSize.width * 3.2, boardSize.width * 0.36)
        let height = cardSize.height * 0.62
        return BoardRect(x: boardSize.width / 2 - width / 2, y: bottomRowY + (cardSize.height - height) / 2,
                    width: width, height: height)
    }

    // MARK: Dropping

    /// Column a dragged run should land in: of the columns where the move is legal, the one whose
    /// top card (or empty slot) overlaps the dragged card most. Nil = snap back.
    public func dropColumn(for state: GameState, from: Int, index: Int, draggedFrame: BoardRect) -> Int? {
        var best: (column: Int, area: Double)?
        for to in state.columns.indices where state.canMove(from: from, index: index, to: to) {
            let target = cardFrames(column: to, cards: state.columns[to]).last ?? slotFrame(column: to)
            let area = target.intersectionArea(draggedFrame)
            if area > 0, area > (best?.area ?? 0) { best = (to, area) }
        }
        return best?.column
    }
}

public struct CardLocation: Hashable, Sendable {
    public let column: Int
    public let index: Int
    public init(column: Int, index: Int) { self.column = column; self.index = index }
}
