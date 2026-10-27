/// Minimal geometry types so board layout stays pure Swift and testable on Linux.
/// The app converts them to CGPoint/CGSize/CGRect at the SwiftUI boundary.
public struct BoardPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct BoardSize: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public static let zero = BoardSize(width: 0, height: 0)
}

public struct BoardRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var center: BoardPoint { BoardPoint(x: midX, y: midY) }

    public func contains(_ p: BoardPoint) -> Bool { p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY }

    public func offsetBy(dx: Double, dy: Double) -> BoardRect {
        BoardRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Area of the overlap with `other` (0 when disjoint).
    public func intersectionArea(_ other: BoardRect) -> Double {
        let w = min(maxX, other.maxX) - max(minX, other.minX)
        let h = min(maxY, other.maxY) - max(minY, other.minY)
        return w > 0 && h > 0 ? w * h : 0
    }

    public func union(_ other: BoardRect) -> BoardRect {
        let nx = min(minX, other.minX), ny = min(minY, other.minY)
        return BoardRect(x: nx, y: ny, width: max(maxX, other.maxX) - nx, height: max(maxY, other.maxY) - ny)
    }
}
