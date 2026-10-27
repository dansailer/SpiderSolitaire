import SpiderCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Achievement badges: a medal (gold when unlocked, grey when locked) with one emblem per
/// achievement. Drawn in a 100 × 100 design space and scaled; rendered by SwiftUI in the app and
/// as SVG for previews.
public enum BadgeArt {
    public static let designSize: Double = 100

    struct Palette {
        let rimLight: RGBA, rimDark: RGBA, faceLight: RGBA, faceDark: RGBA, edge: RGBA, ink: RGBA, shine: RGBA
    }

    static let gold = Palette(
        rimLight: RGBA(1.0, 0.89, 0.50), rimDark: RGBA(0.66, 0.46, 0.10),
        faceLight: RGBA(1.0, 0.95, 0.70), faceDark: RGBA(0.89, 0.68, 0.22),
        edge: RGBA(0.55, 0.37, 0.06), ink: RGBA(0.42, 0.25, 0.03), shine: RGBA(1, 1, 1, 0.45))
    static let grey = Palette(
        rimLight: RGBA(0.86, 0.86, 0.86), rimDark: RGBA(0.55, 0.55, 0.55),
        faceLight: RGBA(0.93, 0.93, 0.93), faceDark: RGBA(0.74, 0.74, 0.74),
        edge: RGBA(0.50, 0.50, 0.50), ink: RGBA(0.52, 0.52, 0.52), shine: RGBA(1, 1, 1, 0.30))

    public static func scene(_ emblem: AchievementEmblem, unlocked: Bool, size: Double) -> VectorScene {
        let pal = unlocked ? gold : grey
        let c = BoardPoint(x: 50, y: 50)
        var items: [VectorItem] = [
            VectorItem(
                path: .circle(center: c, radius: 47),
                fill: .linear(
                    start: BoardPoint(x: 20, y: 5), end: BoardPoint(x: 80, y: 95), from: pal.rimLight, to: pal.rimDark),
                stroke: Stroke(pal.edge, width: 1.5),
                shadow: unlocked ? Shadow(dx: 0, dy: 1.5, blur: 3, color: RGBA(0, 0, 0, 0.35)) : nil),
            VectorItem(
                path: .circle(center: c, radius: 38),
                fill: .radial(center: BoardPoint(x: 42, y: 38), radius: 46, from: pal.faceLight, to: pal.faceDark),
                stroke: Stroke(pal.edge, width: 1.2)),
            // Beaded inner ring.
            VectorItem(
                path: beads(center: c, radius: 42.5, count: 28, size: 1.1), fill: .solid(pal.edge.withAlpha(0.7))),
        ]
        items += emblemItems(emblem, ink: pal.ink)
        // Highlight across the top of the face.
        items.append(VectorItem(path: crescent(), fill: .solid(pal.shine)))
        let s = size / designSize
        return VectorScene(
            size: BoardSize(width: size, height: size),
            items: items.map { $0.transformed(by: .scale(s)) })
    }

    // MARK: Emblems (inside the 26...74 box)

    static func emblemItems(_ emblem: AchievementEmblem, ink: RGBA) -> [VectorItem] {
        func fill(_ p: VectorPath) -> VectorItem { VectorItem(path: p, fill: .solid(ink)) }
        func line(_ p: VectorPath, _ w: Double = 4) -> VectorItem { VectorItem(path: p, stroke: Stroke(ink, width: w)) }
        func pt(_ x: Double, _ y: Double) -> BoardPoint { BoardPoint(x: x, y: y) }

        switch emblem {
        case .star:
            return [fill(star(center: pt(50, 51), outer: 21, inner: 8.5))]
        case .twoPips:
            return [
                fill(SpadePip.path(in: BoardRect(x: 29, y: 38, width: 19, height: 24))),
                fill(heart(in: BoardRect(x: 52, y: 38, width: 21, height: 24))),
            ]
        case .fourPips:
            return [
                fill(SpadePip.path(in: BoardRect(x: 33, y: 31, width: 15, height: 17))),
                fill(heart(in: BoardRect(x: 52, y: 31, width: 16, height: 17))),
                fill(diamond(in: BoardRect(x: 33, y: 52, width: 15, height: 18))),
                fill(club(in: BoardRect(x: 52, y: 52, width: 16, height: 17))),
            ]
        case .laurel:
            return laurel(ink: ink)
        case .closedEye:
            let lid = VectorPath([.move(pt(30, 46)), .curve(pt(38, 60), pt(62, 60), pt(70, 46))])
            var lashes = VectorPath()
            for (x0, y0, x1, y1) in [
                (36.0, 53.0, 33.0, 60.0), (43.0, 56.0, 42.0, 63.5), (50.0, 57.0, 50.0, 64.5),
                (57.0, 56.0, 58.0, 63.5), (64.0, 53.0, 67.0, 60.0),
            ] {
                lashes.append(VectorPath([.move(pt(x0, y0)), .line(pt(x1, y1))]))
            }
            return [line(lid, 4), line(lashes, 2.6)]
        case .crown:
            let body = VectorPath.polygon([
                pt(30, 62), pt(28, 38), pt(40, 50), pt(50, 33), pt(60, 50), pt(72, 38), pt(70, 62),
            ])
            let band = VectorPath.roundedRect(BoardRect(x: 30, y: 64, width: 40, height: 6), radius: 1.5)
            var tips = VectorPath()
            for p in [pt(28, 36), pt(50, 31), pt(72, 36)] { tips.append(.circle(center: p, radius: 3)) }
            return [fill(body), fill(band), fill(tips)]
        case .clock:
            let hands = VectorPath([.move(pt(50, 34)), .line(pt(50, 50)), .line(pt(61, 57))])
            var ticks = VectorPath()
            for i in 0..<12 {
                let a = Double(i) * Double.pi / 6
                let r0 = i % 3 == 0 ? 16.0 : 18.0
                ticks.append(
                    VectorPath([
                        .move(pt(50 + r0 * sin(a), 50 - r0 * cos(a))),
                        .line(pt(50 + 20 * sin(a), 50 - 20 * cos(a))),
                    ]))
            }
            return [
                line(.circle(center: pt(50, 50), radius: 23), 3.5), line(ticks, 2), line(hands, 3.5),
                fill(.circle(center: pt(50, 50), radius: 2.5)),
            ]
        case .target:
            return [
                line(.circle(center: pt(50, 50), radius: 22), 3.5), line(.circle(center: pt(50, 50), radius: 13), 3.5),
                fill(.circle(center: pt(50, 50), radius: 5)),
            ]
        case .sweep:
            // A broom: handle and fanned bristles, with a few motes.
            let handle = VectorPath([.move(pt(66, 28)), .line(pt(47, 54))])
            let head = VectorPath.polygon([pt(44, 50), pt(52, 56), pt(46, 73), pt(27, 66)])
            var bristles = VectorPath()
            for (x0, y0, x1, y1) in [(43.0, 58.0, 34.0, 67.0), (47.0, 60.0, 40.0, 70.0)] {
                bristles.append(VectorPath([.move(pt(x0, y0)), .line(pt(x1, y1))]))
            }
            var motes = VectorPath()
            for (x, y, r) in [(62.0, 66.0, 2.2), (68.0, 60.0, 1.6), (70.0, 69.0, 1.8)] {
                motes.append(.circle(center: pt(x, y), radius: r))
            }
            return [
                line(handle, 4.5), fill(head),
                VectorItem(path: bristles, stroke: Stroke(RGBA(1, 1, 1, 0.35), width: 1.4)),
                fill(motes),
            ]
        case .emptySlot:
            // XP's empty column: a card outline with a dashed inner edge.
            let card = VectorPath.roundedRect(BoardRect(x: 36, y: 29, width: 28, height: 40), radius: 4)
            var dashes = VectorPath()
            let r = BoardRect(x: 41, y: 34, width: 18, height: 30)
            for i in 0..<4 {
                let y = r.minY + Double(i) * 8
                dashes.append(VectorPath([.move(pt(r.minX, y)), .line(pt(r.minX, y + 4))]))
                dashes.append(VectorPath([.move(pt(r.maxX, y)), .line(pt(r.maxX, y + 4))]))
            }
            for i in 0..<3 {
                let x = r.minX + 2 + Double(i) * 6
                dashes.append(VectorPath([.move(pt(x, r.minY)), .line(pt(x + 2.5, r.minY))]))
                dashes.append(VectorPath([.move(pt(x, r.maxY)), .line(pt(x + 2.5, r.maxY))]))
            }
            return [line(card, 3.5), line(dashes, 1.8)]
        case .threeStars:
            return [
                fill(star(center: pt(34, 55), outer: 10, inner: 4)),
                fill(star(center: pt(50, 42), outer: 12.5, inner: 5)),
                fill(star(center: pt(66, 55), outer: 10, inner: 4)),
            ]
        case .flame:
            let outer = VectorPath([
                .move(pt(50, 27)), .curve(pt(56, 38), pt(68, 45), pt(66, 59)),
                .curve(pt(65, 68), pt(58, 73), pt(50, 73)), .curve(pt(41, 73), pt(34, 67), pt(34, 59)),
                .curve(pt(34, 50), pt(41, 47), pt(42, 40)), .curve(pt(46, 45), pt(46, 50), pt(45, 53)),
                .curve(pt(50, 47), pt(52, 36), pt(50, 27)), .close,
            ])
            let inner = VectorPath([
                .move(pt(51, 50)), .curve(pt(56, 56), pt(60, 60), pt(58, 65)),
                .curve(pt(57, 69), pt(54, 71), pt(50, 71)), .curve(pt(46, 71), pt(42, 68), pt(43, 63)),
                .curve(pt(44, 58), pt(50, 57), pt(51, 50)), .close,
            ])
            return [fill(outer), VectorItem(path: inner, fill: .solid(RGBA(1, 1, 1, 0.35)))]
        case .ribbon:
            let tails = VectorPath.polygon([pt(40, 52), pt(33, 74), pt(40, 70), pt(45, 76), pt(49, 56)])
            let tails2 = VectorPath.polygon([pt(60, 52), pt(67, 74), pt(60, 70), pt(55, 76), pt(51, 56)])
            return [
                fill(tails), fill(tails2), fill(.circle(center: pt(50, 43), radius: 15)),
                VectorItem(
                    path: .circle(center: pt(50, 43), radius: 10), stroke: Stroke(RGBA(1, 1, 1, 0.45), width: 1.8)),
            ]
        case .hundred:
            let one = VectorPath([.move(pt(28, 43)), .line(pt(34, 38)), .line(pt(34, 62))])
            let zero1 = ellipse(center: pt(47, 50), rx: 6.5, ry: 11.5)
            let zero2 = ellipse(center: pt(65, 50), rx: 6.5, ry: 11.5)
            return [line(one, 4), line(zero1, 4), line(zero2, 4)]
        }
    }

    // MARK: Shapes

    static func star(center c: BoardPoint, outer: Double, inner: Double) -> VectorPath {
        .polygon(
            (0..<10).map { i in
                let a = Double(i) * Double.pi / 5
                let r = i % 2 == 0 ? outer : inner
                return BoardPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
            })
    }

    static func ellipse(center c: BoardPoint, rx: Double, ry: Double) -> VectorPath {
        VectorPath.circle(center: BoardPoint(x: 0, y: 0), radius: 1)
            .transformed(by: Affine2D(a: rx, b: 0, c: 0, d: ry, tx: c.x, ty: c.y))
    }

    /// Heart in a box (width : height about 0.9).
    static func heart(in r: BoardRect) -> VectorPath {
        let h = min(r.height, r.width / 0.9), w = h * 0.9
        let x0 = r.midX - w / 2, y0 = r.midY - h / 2
        func p(_ x: Double, _ y: Double) -> BoardPoint { BoardPoint(x: x0 + x * w, y: y0 + y * h) }
        return VectorPath([
            .move(p(0.5, 0.25)),
            .curve(p(0.58, 0.02), p(1.0, 0.0), p(1.0, 0.33)),
            .curve(p(1.0, 0.58), p(0.66, 0.76), p(0.5, 1.0)),
            .curve(p(0.34, 0.76), p(0.0, 0.58), p(0.0, 0.33)),
            .curve(p(0.0, 0.0), p(0.42, 0.02), p(0.5, 0.25)), .close,
        ])
    }

    static func diamond(in r: BoardRect) -> VectorPath {
        let h = min(r.height, r.width / 0.75), w = h * 0.75
        return .polygon([
            BoardPoint(x: r.midX, y: r.midY - h / 2), BoardPoint(x: r.midX + w / 2, y: r.midY),
            BoardPoint(x: r.midX, y: r.midY + h / 2), BoardPoint(x: r.midX - w / 2, y: r.midY),
        ])
    }

    /// Club: three leaves and a flared stem.
    static func club(in r: BoardRect) -> VectorPath {
        let h = min(r.height, r.width), x0 = r.midX - h / 2, y0 = r.midY - h / 2
        func p(_ x: Double, _ y: Double) -> BoardPoint { BoardPoint(x: x0 + x * h, y: y0 + y * h) }
        var path = VectorPath.circle(center: p(0.5, 0.24), radius: 0.22 * h)
        path.append(.circle(center: p(0.25, 0.56), radius: 0.22 * h))
        path.append(.circle(center: p(0.75, 0.56), radius: 0.22 * h))
        path.append(.polygon([p(0.46, 0.4), p(0.54, 0.4), p(0.58, 0.86), p(0.72, 1.0), p(0.28, 1.0), p(0.42, 0.86)]))
        return path
    }

    /// Two laurel branches meeting at the bottom, leaves along each stem.
    static func laurel(ink: RGBA) -> [VectorItem] {
        var leaves = VectorPath()
        var stems = VectorPath()
        for side in [-1.0, 1.0] {
            let p0 = BoardPoint(x: 50 + side * 3, y: 72), p1 = BoardPoint(x: 50 + side * 24, y: 67)
            let p2 = BoardPoint(x: 50 + side * 27, y: 42), p3 = BoardPoint(x: 50 + side * 14, y: 27)
            stems.append(VectorPath([.move(p0), .curve(p1, p2, p3)]))
            for (i, t) in [0.12, 0.28, 0.44, 0.6, 0.76, 0.92].enumerated() {
                let u = 1 - t
                let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
                let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
                let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
                let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
                let along = atan2(dy, dx) * 180 / Double.pi - 90
                // Alternate leaves inside and outside the stem, tilted towards the tip.
                let outward = i % 2 == 0 ? 1.0 : -1.0
                let tilt = along + side * outward * 35
                let off = 3.2 * outward * side
                let nx = -dy, ny = dx
                let len = (nx * nx + ny * ny).squareRoot()
                let leaf = ellipse(center: BoardPoint(x: 0, y: 0), rx: 2.4, ry: 5.6)
                    .transformed(
                        by: Affine2D.rotation(degrees: tilt)
                            .then(.translation(x + off * nx / len, y + off * ny / len)))
                leaves.append(leaf)
            }
        }
        return [VectorItem(path: stems, stroke: Stroke(ink, width: 2)), VectorItem(path: leaves, fill: .solid(ink))]
    }

    static func beads(center c: BoardPoint, radius: Double, count: Int, size: Double) -> VectorPath {
        var p = VectorPath()
        for i in 0..<count {
            let a = Double(i) * 2 * Double.pi / Double(count)
            p.append(.circle(center: BoardPoint(x: c.x + radius * sin(a), y: c.y - radius * cos(a)), radius: size))
        }
        return p
    }

    /// Soft shine on the upper face.
    static func crescent() -> VectorPath {
        VectorPath([
            .move(BoardPoint(x: 22, y: 42)),
            .curve(BoardPoint(x: 26, y: 20), BoardPoint(x: 52, y: 8), BoardPoint(x: 74, y: 22)),
            .curve(BoardPoint(x: 56, y: 15), BoardPoint(x: 32, y: 22), BoardPoint(x: 22, y: 42)), .close,
        ])
    }
}

/// The score box's Time line.
public enum PlayClock {
    /// m:ss, or h:mm:ss from an hour on.
    public static func text(_ seconds: Int) -> String {
        let s = max(0, seconds)
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        if s >= 3600 { return "\(s / 3600):" + two((s / 60) % 60) + ":" + two(s % 60) }
        return "\(s / 60):" + two(s % 60)
    }
}
