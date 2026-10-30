import SpiderCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The win animation as a pure function of time, in the style of classic Windows Solitaire: every
/// card of the completed suits leaves the foundation, pile by pile and king first, and bounces off
/// the bottom of the window until it leaves at the left or right edge; the app paints each card's
/// path into a trail layer (`trailStep`). Firework bursts start once the cascade is under way and
/// end in a finale of a few bursts at once. The view samples this every frame; nothing is stored.
///
/// Times are layout-free (a card's flight lasts `Flight.duration` at any window size) so the show
/// lasts `endTime` whatever the size; positions need a `BoardLayout`.
public struct WinCelebration: Sendable {
    /// Seconds between two cards leaving the foundation.
    static let launchInterval: Double = 0.095
    /// Share of cards that fly to the left (the foundation sits at the left, so fewer go that way).
    static let leftShare: Double = 0.3
    /// Horizontal speed in board widths per second (left-goers drift slowly so they stay a while).
    static let rightSpeed: ClosedRange<Double> = 0.36...0.6
    static let leftSpeed: ClosedRange<Double> = 0.1...0.16
    /// Nominal distance to the edge, in board widths, that sets each flight's duration.
    static let rightDistance: Double = 1.0
    static let leftDistance: Double = 0.2
    /// Height of the first hop above the foundation, in board heights (capped below the top edge).
    static let apex: ClosedRange<Double> = 0.3...0.8
    /// Board heights per second squared.
    static let gravity: Double = 1.6
    static let restitution: Double = 0.72

    /// Simulation step at which the app stamps each card into the trail layer (frame-rate free).
    public static let trailStep: Double = 1.0 / 30
    /// The trail layer fades by half in this many seconds (in `trailFadeInterval` steps), so the
    /// felt shows recent paths rather than a solid wall of 104 cards.
    public static let trailHalfLife: Double = 0.5
    public static let trailFadeInterval: Double = 0.125

    static let burstsStart: Double = 2.0
    static let firstBurstGap: Double = 1.0
    static let lastBurstGap: Double = 0.45
    /// Quiet moment before the finale, and the finale's bursts.
    static let finaleLead: Double = 1.0
    static let finaleBursts: Int = 3
    static let finaleStagger: Double = 0.18
    static let particlesPerBurst: Int = 28
    static let particleLife: Double = 1.4
    public static let paletteSize: Int = 6

    /// One firework spark.
    public struct Spark: Hashable, Sendable {
        public let center: BoardPoint
        public let alpha: Double
        public let radius: Double
        /// Picks from the view's palette.
        public let colorIndex: Int
    }

    /// One card's trip from its foundation pile off the edge of the board.
    public struct Flight: Hashable, Sendable {
        public let card: Card
        /// Foundation slot (0 is the leftmost pile).
        public let pile: Int
        public let start: Double
        /// Seconds from launch until the card has left the board.
        public let duration: Double
        /// +1 flies right, -1 left.
        let direction: Double
        /// Requested first-hop height in board heights.
        let apex: Double

        public var end: Double { start + duration }
    }

    struct Burst: Hashable, Sendable {
        let start: Double
        /// Centre as fractions of the board size.
        let origin: BoardPoint
        let colorIndex: Int
        /// Spark speeds as fractions of the board's shorter side, per second.
        let speeds: [Double]
        let angles: [Double]
    }

    public let suits: [Suit]
    /// Every flight in launch order: the rightmost pile first (it is on top), each king to ace.
    public let flights: [Flight]
    let bursts: [Burst]
    /// The last card has left and the last spark has faded.
    public let endTime: Double

    /// Cards that appear in the animation (ids are negative so they never clash with the deck).
    public var cards: [Card] { flights.map(\.card) }

    public init(suits: [Suit], seed: UInt64) {
        self.suits = suits.isEmpty ? [Suit.spades] : suits
        var rng = SeededGenerator(seed: seed)
        func unit() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }
        func pick(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + (range.upperBound - range.lowerBound) * unit()
        }

        let ranks: [Rank] = Rank.allCases.reversed()
        var flights: [Flight] = []
        for pile in self.suits.indices.reversed() {
            for rank in ranks {
                let card = Card(id: -1000 - flights.count, suit: self.suits[pile], rank: rank, isFaceUp: true)
                let left = unit() < WinCelebration.leftShare
                let duration =
                    left
                    ? WinCelebration.leftDistance / pick(WinCelebration.leftSpeed)
                    : WinCelebration.rightDistance / pick(WinCelebration.rightSpeed)
                flights.append(
                    Flight(
                        card: card, pile: pile, start: Double(flights.count) * WinCelebration.launchInterval,
                        duration: duration, direction: left ? -1 : 1, apex: pick(WinCelebration.apex)))
            }
        }
        self.flights = flights
        let lastExit = flights.map(\.end).max() ?? 0

        // Bursts come closer together as the cascade goes on, pause, then end in a finale.
        let finale = max(WinCelebration.burstsStart + 1, lastExit - WinCelebration.finaleLead)
        let quietFrom = finale - 0.6
        var bursts: [Burst] = []
        var colour = 0
        func burst(at start: Double, x: Double, y: Double) {
            let count = WinCelebration.particlesPerBurst
            let angles = (0..<count).map { i in 2 * Double.pi * Double(i) / Double(count) + 0.2 * unit() }
            let speeds = (0..<count).map { _ in 0.22 + 0.22 * unit() }
            bursts.append(
                Burst(
                    start: start, origin: BoardPoint(x: x, y: y), colorIndex: colour % WinCelebration.paletteSize,
                    speeds: speeds, angles: angles))
            colour += 1
        }
        var bt = WinCelebration.burstsStart
        while bt < quietFrom {
            burst(at: bt, x: 0.15 + 0.7 * unit(), y: 0.1 + 0.4 * unit())
            let progress = (bt - WinCelebration.burstsStart) / max(1, quietFrom - WinCelebration.burstsStart)
            let gap =
                WinCelebration.firstBurstGap + (WinCelebration.lastBurstGap - WinCelebration.firstBurstGap) * progress
            bt += gap * (0.8 + 0.4 * unit())
        }
        for i in 0..<WinCelebration.finaleBursts {
            let x = (Double(i) + 0.5) / Double(WinCelebration.finaleBursts) + 0.08 * (unit() - 0.5)
            burst(at: finale + Double(i) * WinCelebration.finaleStagger, x: x, y: 0.15 + 0.15 * unit())
        }
        self.bursts = bursts
        endTime = max(lastExit, (bursts.map(\.start).max() ?? 0) + WinCelebration.particleLife)
    }

    // MARK: Geometry

    /// Centre of the pile a flight leaves from.
    func origin(of flight: Flight, layout: BoardLayout) -> BoardPoint {
        let slots = layout.foundationFrames(count: suits.count)
        return slots[min(flight.pile, slots.count - 1)].center
    }

    /// Centre of `flight`'s card `tau` seconds after launch, or nil before launch and after it left.
    func position(of flight: Flight, tau: Double, layout: BoardLayout) -> BoardPoint? {
        guard tau >= 0, tau < flight.duration else { return nil }
        let w = layout.boardSize.width, h = layout.boardSize.height
        let card = layout.cardSize
        let o = origin(of: flight, layout: layout)
        // Reaches just past the edge exactly at `duration`, whatever the layout.
        let distance = flight.direction > 0 ? w + card.width / 2 - o.x : o.x + card.width / 2
        let x = o.x + flight.direction * distance * tau / flight.duration

        let g = WinCelebration.gravity * h
        let floorY = h - card.height / 2
        let y0 = min(o.y, floorY)
        let apex = max(0, min(flight.apex * h, y0 - card.height / 2))
        let vy = -(2 * g * apex).squareRoot()
        // First flight: y0 + vy t + g t²/2 until it reaches the floor.
        let disc = vy * vy + 2 * g * (floorY - y0)
        let firstImpact = (-vy + disc.squareRoot()) / g
        if tau <= firstImpact {
            return BoardPoint(x: x, y: y0 + vy * tau + g * tau * tau / 2)
        }
        // Then hops of shrinking height: each leaves the floor at `restitution` times the impact speed.
        var speed = (vy + g * firstImpact) * WinCelebration.restitution
        var s = tau - firstImpact
        while speed > 1 {
            let hop = 2 * speed / g
            if s <= hop { return BoardPoint(x: x, y: floorY - speed * s + g * s * s / 2) }
            s -= hop
            speed *= WinCelebration.restitution
        }
        return BoardPoint(x: x, y: floorY) // sliding along the floor
    }

    /// Cards in the air at `t`, in launch order (later ones drawn on top).
    public func cardsInFlight(at t: Double, layout: BoardLayout) -> [(card: Card, center: BoardPoint)] {
        flights.compactMap { flight in
            position(of: flight, tau: t - flight.start, layout: layout).map { (flight.card, $0) }
        }
    }

    /// The card still on top of each pile at `t` (piles empty as their cards leave), leftmost first.
    public func pileTops(at t: Double) -> [(pile: Int, card: Card)] {
        var tops: [Int: Card] = [:]
        for flight in flights.reversed() where flight.start > t {
            tops[flight.pile] = flight.card
        }
        return tops.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Firework sparks at `t` (drawn under the cards).
    public func sparks(at t: Double, layout: BoardLayout) -> [Spark] {
        let w = layout.boardSize.width, h = layout.boardSize.height
        let reach = min(w, h)
        let sparkGravity = 0.25 * h
        let radius = max(1.5, layout.cardSize.width * 0.035)
        var sparks: [Spark] = []
        for burst in bursts {
            let age = t - burst.start
            guard age >= 0, age < WinCelebration.particleLife else { continue }
            let alpha = 1 - age / WinCelebration.particleLife
            for i in burst.angles.indices {
                let v = burst.speeds[i] * reach
                let p = BoardPoint(
                    x: burst.origin.x * w + cos(burst.angles[i]) * v * age,
                    y: burst.origin.y * h + sin(burst.angles[i]) * v * age + sparkGravity * age * age / 2)
                sparks.append(Spark(center: p, alpha: alpha, radius: radius, colorIndex: burst.colorIndex))
            }
        }
        return sparks
    }

    /// Start times of the bursts (for tests and sound cues).
    public var burstTimes: [Double] { bursts.map(\.start) }
}
