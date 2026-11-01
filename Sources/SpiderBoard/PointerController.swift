import SpiderCore

/// Turns raw pointer input (press, drag, release, with timestamps) into game actions.
/// The SwiftUI view forwards one DragGesture(minimumDistance: 0) here; all decisions live here so
/// they are unit-tested on Linux.
/// The one gesture whose click skipped a running deal: the rest of it is ignored, so it cannot
/// also pick up or move a card that was still in the air. Gestures are told apart by their
/// start point, like `PointerController` does: a different start means the suppressed gesture
/// was cancelled without an end event, and the stale suppression is dropped.
public struct GestureSuppression: Hashable, Sendable {
    public private(set) var start: BoardPoint?

    public init() {}

    public mutating func suppress(start: BoardPoint) { self.start = start }

    /// Whether a change of the gesture that began at `start` is ignored.
    public mutating func ignoresChange(start: BoardPoint) -> Bool {
        guard let suppressed = self.start else { return false }
        if suppressed == start { return true }
        self.start = nil
        return false
    }

    /// Whether the end of the gesture that began at `start` is ignored. Ends the suppression.
    public mutating func ignoresEnd(start: BoardPoint) -> Bool {
        defer { self.start = nil }
        return self.start == start
    }

    public mutating func reset() { start = nil }
}

public struct PointerController: Sendable {
    /// Pointer travel (points) before a press becomes a drag.
    public static let dragThreshold: Double = 3
    /// Default for `doubleClickInterval` when the system value is not known (Linux tests).
    public static let defaultDoubleClickInterval: Double = 0.35
    /// Max distance (points) between two clicks that still makes them one double-click.
    public static let doubleClickSlop: Double = 5

    /// A run currently being dragged.
    public struct Drag: Hashable, Sendable {
        public let from: Int
        public let index: Int
        public var translation: BoardSize
    }

    public enum Result: Hashable, Sendable {
        /// Nothing to do (click on felt, a card with nowhere to go, second click of a double-click, ...).
        case none
        /// Run the action. For drags the view should animate cards to their new places.
        case perform(Action)
        /// A drag ended somewhere illegal: animate the run back.
        case snapBack
        /// Click on the score box: show the next hint (XP behaviour).
        case hint
    }

    public private(set) var drag: Drag?
    private var pressed: CardLocation?
    /// Where the current press began; a different start means a new gesture (the old one was
    /// cancelled without an end event), so stale state is dropped.
    private var pressStart: BoardPoint?
    /// The last click that acted on a card. Further clicks at the same spot within
    /// `doubleClickInterval` belong to the same double-click and are ignored, so a double-click
    /// moves a run once instead of also moving whatever card ends up under the pointer.
    private var lastClick: (point: BoardPoint, time: Double)?

    /// Max seconds between clicks at the same spot that make them one double-click. The app sets
    /// the user's macOS setting here.
    public var doubleClickInterval: Double = PointerController.defaultDoubleClickInterval

    public init() {}

    /// Ids-free query for the view: is the card at (column, index) part of the dragged run?
    public func isDragging(column: Int, index: Int) -> Bool {
        guard let drag else { return false }
        return column == drag.from && index >= drag.index
    }

    public mutating func pointerChanged(
        start: BoardPoint, translation: BoardSize, state: GameState, layout: BoardLayout
    ) {
        if pressStart != start {
            drag = nil
            pressStart = start
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

    public mutating func pointerEnded(
        start: BoardPoint, translation: BoardSize, time: Double,
        state: GameState, layout: BoardLayout
    ) -> Result {
        defer { pressed = nil; pressStart = nil; drag = nil }

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

        if layout.scoreBoxFrame.contains(start) {
            lastClick = nil
            return .hint
        }

        if continuesDoubleClick(start: start, translation: translation, time: time) { return .none }

        guard let location = layout.card(at: start, in: state) else {
            lastClick = nil
            return .none
        }
        // A single click sends the card and the run on top of it to the best place.
        lastClick = (start, time)
        if let to = state.bestDestination(from: location.column, index: location.index) {
            return .perform(.move(from: location.column, index: location.index, to: to))
        }
        return .none
    }

    /// Whether a press at `start` (moved by `translation` so far) at `time` is a further click of
    /// the double-click whose first click already acted. Such a click does nothing.
    public func continuesDoubleClick(start: BoardPoint, translation: BoardSize, time: Double) -> Bool {
        guard let last = lastClick, !PointerController.exceedsThreshold(translation) else { return false }
        return time - last.time <= doubleClickInterval && PointerController.isNear(last.point, start)
    }

    /// Forget an in-flight gesture (e.g. new game started mid-drag).
    public mutating func reset() {
        drag = nil
        pressed = nil
        pressStart = nil
        lastClick = nil
    }

    static func isNear(_ a: BoardPoint, _ b: BoardPoint) -> Bool {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy <= doubleClickSlop * doubleClickSlop
    }

    /// Compares squared lengths (no square root, so no libm dependency on Linux).
    static func exceedsThreshold(_ s: BoardSize) -> Bool {
        s.width * s.width + s.height * s.height >= dragThreshold * dragThreshold
    }
}
