import SpiderCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The win animation as a pure function of time: completed-suit cards launch from the
/// foundation and bounce across the felt leaving short trails (classic Windows style), while
/// fireworks burst overhead. The view samples `sprites(at:)` every frame; nothing is stored.
public struct WinCelebration: Sendable {
    /// Seconds until everything has left the screen; the app shows the dialog after this.
    public static let nominalDuration: Double = 10
    static let launchInterval: Double = 0.22
    static let lastLaunch: Double = 6.8
    static let trailLength: Int = 6
    static let trailSpacing: Double = 0.028
    static let restitution: Double = 0.72
    static let burstInterval: Double = 0.45
    static let particlesPerBurst: Int = 28
    static let particleLife: Double = 1.4

    public enum Kind: Hashable, Sendable {
        case card(id: Int)
        /// Firework spark; `colorIndex` picks from the view's palette.
        case spark(colorIndex: Int)
    }

    public struct Sprite: Hashable, Sendable {
        public let kind: Kind
        public let center: BoardPoint
        public let alpha: Double
        /// Spark radius (points); unused for cards.
        public let radius: Double
    }

    struct Launch: Hashable, Sendable {
        let cardID: Int
        let start: Double
        let origin: BoardPoint
        let vx: Double
        let vy: Double
    }

    struct Burst: Hashable, Sendable {
        let start: Double
        let origin: BoardPoint
        let colorIndex: Int
        let speeds: [Double]
        let angles: [Double]
    }

    public static let paletteSize: Int = 6

    public let boardSize: BoardSize
    public let cardSize: BoardSize
    /// Cards that appear in the animation (ids are negative so they never clash with the deck).
    public let cards: [Card]
    let launches: [Launch]
    let bursts: [Burst]
    let gravity: Double
    let floorY: Double

    public init(layout: BoardLayout, suits: [Suit], seed: UInt64) {
        boardSize = layout.boardSize
        cardSize = layout.cardSize
        let w = layout.boardSize.width, h = layout.boardSize.height
        gravity = 2.2 * h
        floorY = h - layout.cardSize.height / 2

        var rng = SeededGenerator(seed: seed)
        func unit() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }

        let suitList = suits.isEmpty ? [Suit.spades] : suits
        let ranks: [Rank] = [.king, .queen, .jack, .ten]
        let slots = layout.foundationFrames(count: suitList.count)

        var cards: [Card] = []
        var launches: [Launch] = []
        var t = 0.0
        var n = 0
        launchLoop: for rank in ranks {
            for (slot, suit) in suitList.enumerated() {
                if t > WinCelebration.lastLaunch { break launchLoop }
                let card = Card(id: -1000 - n, suit: suit, rank: rank, isFaceUp: true)
                cards.append(card)
                let origin = slots[slot].center
                // Always rightwards and fast enough to leave the screen well before the end.
                let vx = w * (0.38 + 0.3 * unit())
                let vy = -h * (0.4 + 0.9 * unit())
                launches.append(Launch(cardID: card.id, start: t, origin: origin, vx: vx, vy: vy))
                t += WinCelebration.launchInterval
                n += 1
            }
        }
        self.cards = cards
        self.launches = launches

        var bursts: [Burst] = []
        var bt = 0.3
        var colour = 0
        while bt < WinCelebration.nominalDuration - WinCelebration.particleLife - 0.5 {
            let origin = BoardPoint(x: w * (0.15 + 0.7 * unit()), y: h * (0.1 + 0.4 * unit()))
            let count = WinCelebration.particlesPerBurst
            let angles = (0..<count).map { i in 2 * Double.pi * Double(i) / Double(count) + 0.2 * unit() }
            let speeds = (0..<count).map { _ in min(w, h) * (0.22 + 0.22 * unit()) }
            bursts.append(
                Burst(
                    start: bt, origin: origin, colorIndex: colour % WinCelebration.paletteSize,
                    speeds: speeds, angles: angles))
            colour += 1
            bt += WinCelebration.burstInterval * (0.7 + 0.6 * unit())
        }
        self.bursts = bursts
    }

    /// Centre of a launched card `tau` seconds after its launch (nil before launch).
    func position(of launch: Launch, tau: Double) -> BoardPoint? {
        guard tau >= 0 else { return nil }
        let x = launch.origin.x + launch.vx * tau
        let g = gravity
        let y0 = min(launch.origin.y, floorY)
        // First flight: y0 + vy t + g t²/2 until it reaches the floor.
        let disc = launch.vy * launch.vy + 2 * g * (floorY - y0)
        let firstImpact = (-launch.vy + disc.squareRoot()) / g
        if tau <= firstImpact {
            return BoardPoint(x: x, y: y0 + launch.vy * tau + g * tau * tau / 2)
        }
        // Then hops of shrinking height: each leaves the floor at e^k times the impact speed.
        var speed = (launch.vy + g * firstImpact) * WinCelebration.restitution
        var s = tau - firstImpact
        while speed > 1 {
            let hop = 2 * speed / g
            if s <= hop { return BoardPoint(x: x, y: floorY - speed * s + g * s * s / 2) }
            s -= hop
            speed *= WinCelebration.restitution
        }
        return BoardPoint(x: x, y: floorY) // sliding along the floor
    }

    private func isOnScreen(_ p: BoardPoint) -> Bool {
        p.x - cardSize.width / 2 < boardSize.width && p.x + cardSize.width / 2 > 0
    }

    /// Everything to draw at `t` seconds after the win. Trails come first (drawn underneath).
    public func sprites(at t: Double) -> [Sprite] {
        var trails: [Sprite] = []
        var heads: [Sprite] = []
        for launch in launches {
            let tau = t - launch.start
            guard let head = position(of: launch, tau: tau), isOnScreen(head) else { continue }
            for k in stride(from: WinCelebration.trailLength, through: 1, by: -1) {
                let past = tau - Double(k) * WinCelebration.trailSpacing
                guard let p = position(of: launch, tau: past), isOnScreen(p) else { continue }
                let alpha = 0.55 * (1 - Double(k) / Double(WinCelebration.trailLength + 1))
                trails.append(Sprite(kind: .card(id: launch.cardID), center: p, alpha: alpha, radius: 0))
            }
            heads.append(Sprite(kind: .card(id: launch.cardID), center: head, alpha: 1, radius: 0))
        }

        var sparks: [Sprite] = []
        let sparkGravity = 0.25 * boardSize.height
        for burst in bursts {
            let age = t - burst.start
            guard age >= 0, age < WinCelebration.particleLife else { continue }
            let alpha = 1 - age / WinCelebration.particleLife
            for i in burst.angles.indices {
                let v = burst.speeds[i]
                let p = BoardPoint(
                    x: burst.origin.x + cos(burst.angles[i]) * v * age,
                    y: burst.origin.y + sin(burst.angles[i]) * v * age + sparkGravity * age * age / 2)
                sparks.append(
                    Sprite(
                        kind: .spark(colorIndex: burst.colorIndex), center: p,
                        alpha: alpha, radius: max(1.5, cardSize.width * 0.035)))
            }
        }
        return trails + heads + sparks
    }
}
