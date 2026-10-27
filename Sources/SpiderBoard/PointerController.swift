import SpiderCore

/// Turns raw pointer input (press, drag, release, with timestamps) into game actions.
/// The SwiftUI view forwards one DragGesture(minimumDistance: 0) here; all decisions live here so
/// they are unit-tested on Linux.
public struct PointerController: Sendable {
    /// Pointer travel (points) before a press becomes a drag.
    public static let dragThreshold: Double = 3
    /// Max seconds between two clicks on the same card to count as a double-click.
    public static let doubleClickInterval: Double = 0.35

    /// A run currently being dragged.
    public struct Drag: Hashable, Sendable {
        public let from: Int
        public let index: Int
        public var translation: Size
    }

    public enum Result: Hashable, Sendable {
        /// Nothing to do (click on felt, first click of a double-click, ...).
        case none
        /// Run the action. For drags the view should animate cards to their new places.
        case perform(Action)
        /// A drag ended somewhere illegal: animate the run back.
        case snapBack
    }

    public private(set) var drag: Drag?
    private var pressed: CardLocation?
    private var lastClick: (location: CardLocation, time: Double)?

    public init() {}

    /// Ids-free query for the view: is the card at (column, index) part of the dragged run?
    public func isDragging(column: Int, index: Int) -> Bool {
        guard let drag else { return false }
        return column == drag.from && index >= drag.index
    }

    public mutating func pointerChanged(start: Point, translation: Size, state: GameState, layout: BoardLayout) {
        if drag == nil, pressed == nil {
            pressed = layout.card(at: start, in: state)
        }
        guard let pressed, PointerController.exceedsThreshold(translation) else { return }
        if var current = drag {
            current.translation = translation
            drag = current
        } else if state.canPickUp(column: pressed.column, from: pressed.index), !state.isWon {
            drag = Drag(from: pressed.column, index: pressed.index, translation: translation)
        }
    }

    public mutating func pointerEnded(start: Point, translation: Size, time: Double,
                                      state: GameState, layout: BoardLayout) -> Result {
        defer { pressed = nil; drag = nil }

        if let drag {
            lastClick = nil
            let origin = layout.cardFrames(column: drag.from, cards: state.columns[drag.from])[drag.index]
            let dragged = origin.offsetBy(dx: translation.width, dy: translation.height)
            guard let to = layout.dropColumn(for: state, from: drag.from, index: drag.index, draggedFrame: dragged)
            else { return .snapBack }
            return .perform(.move(from: drag.from, index: drag.index, to: to))
        }

        // A click (no drag). A press that wandered over the threshold on an unliftable card is not a click.
        guard !PointerController.exceedsThreshold(translation) else { return .none }

        if let stock = layout.stockHitFrame(dealsRemaining: state.dealsRemaining), stock.contains(start) {
            lastClick = nil
            return .perform(.deal)
        }

        guard let location = layout.card(at: start, in: state) else {
            lastClick = nil
            return .none
        }
        if let last = lastClick, last.location == location, time - last.time <= PointerController.doubleClickInterval {
            lastClick = nil
            if let to = state.bestDestination(from: location.column, index: location.index) {
                return .perform(.move(from: location.column, index: location.index, to: to))
            }
            return .none
        }
        lastClick = (location, time)
        return .none
    }

    /// Forget an in-flight gesture (e.g. new game started mid-drag).
    public mutating func reset() {
        drag = nil
        pressed = nil
        lastClick = nil
    }

    /// Compares squared lengths (no square root, so no libm dependency on Linux).
    static func exceedsThreshold(_ s: Size) -> Bool {
        s.width * s.width + s.height * s.height >= dragThreshold * dragThreshold
    }
}
