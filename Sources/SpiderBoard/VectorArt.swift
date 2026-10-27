#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum VectorMath {
    static func cos(_ x: Double) -> Double { libmCos(x) }
    static func sin(_ x: Double) -> Double { libmSin(x) }
    static func squareRoot(_ x: Double) -> Double { x.squareRoot() }
}

// Free functions so the C library's cos/sin are not shadowed by VectorMath's own members.
private func libmCos(_ x: Double) -> Double { cos(x) }
private func libmSin(_ x: Double) -> Double { sin(x) }

/// Resolution-independent artwork (card back, app icon) as plain data, so one description is drawn
/// by SwiftUI (`VectorSceneView`), by CoreGraphics (the SpiderIcon tool) and as SVG (previews and
/// tests on Linux). Coordinates are top-left origin, y down, in points.

public struct RGBA: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }
}

/// 2-D affine transform: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
public struct Affine2D: Hashable, Sendable {
    public var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static let identity = Affine2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    public static func translation(_ dx: Double, _ dy: Double) -> Affine2D {
        Affine2D(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
    }
    /// Uniform scale only: artwork never gets separate x/y factors.
    public static func scale(_ s: Double) -> Affine2D { Affine2D(a: s, b: 0, c: 0, d: s, tx: 0, ty: 0) }
    /// Clockwise on screen (y down) for positive degrees.
    public static func rotation(degrees: Double) -> Affine2D {
        let r = degrees * Double.pi / 180
        let cs = VectorMath.cos(r), sn = VectorMath.sin(r)
        return Affine2D(a: cs, b: sn, c: -sn, d: cs, tx: 0, ty: 0)
    }
    /// `self` first, then `next`.
    public func then(_ next: Affine2D) -> Affine2D {
        Affine2D(
            a: next.a * a + next.c * b, b: next.b * a + next.d * b,
            c: next.a * c + next.c * d, d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx, ty: next.b * tx + next.d * ty + next.ty)
    }
    public func apply(_ p: BoardPoint) -> BoardPoint {
        BoardPoint(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }
    /// Length scale (for line widths and radii); exact for rotation + uniform scale.
    public var lengthScale: Double { VectorMath.squareRoot(abs(a * d - b * c)) }
}

public enum PathCommand: Hashable, Sendable {
    case move(BoardPoint)
    case line(BoardPoint)
    case curve(BoardPoint, BoardPoint, BoardPoint) // control 1, control 2, end
    case close
}

public struct VectorPath: Hashable, Sendable {
    public var commands: [PathCommand]
    public init(_ commands: [PathCommand] = []) { self.commands = commands }

    public mutating func append(_ other: VectorPath) { commands += other.commands }

    public func transformed(by t: Affine2D) -> VectorPath {
        VectorPath(
            commands.map { (command: PathCommand) -> PathCommand in
                switch command {
                case .move(let p): return .move(t.apply(p))
                case .line(let p): return .line(t.apply(p))
                case .curve(let c1, let c2, let p): return .curve(t.apply(c1), t.apply(c2), t.apply(p))
                case .close: return .close
                }
            })
    }

    /// Bounding box of all points, control points included (exact for the shapes used here,
    /// whose control points stay inside the outline's extremes).
    public var bounds: BoardRect {
        var xs: [Double] = []
        var ys: [Double] = []
        for command in commands {
            switch command {
            case .move(let p), .line(let p): xs.append(p.x); ys.append(p.y)
            case .curve(let c1, let c2, let p): xs += [c1.x, c2.x, p.x]; ys += [c1.y, c2.y, p.y]
            case .close: break
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return BoardRect(x: 0, y: 0, width: 0, height: 0)
        }
        return BoardRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static func rect(_ r: BoardRect) -> VectorPath {
        VectorPath([
            .move(BoardPoint(x: r.minX, y: r.minY)), .line(BoardPoint(x: r.maxX, y: r.minY)),
            .line(BoardPoint(x: r.maxX, y: r.maxY)), .line(BoardPoint(x: r.minX, y: r.maxY)), .close,
        ])
    }

    /// Rounded rectangle with circular corners (cubic approximation, k = 0.5523).
    public static func roundedRect(_ r: BoardRect, radius: Double) -> VectorPath {
        let rad = max(0, min(radius, r.width / 2, r.height / 2))
        let k = rad * 0.5523
        func p(_ x: Double, _ y: Double) -> BoardPoint { BoardPoint(x: x, y: y) }
        return VectorPath([
            .move(p(r.minX + rad, r.minY)),
            .line(p(r.maxX - rad, r.minY)),
            .curve(p(r.maxX - rad + k, r.minY), p(r.maxX, r.minY + rad - k), p(r.maxX, r.minY + rad)),
            .line(p(r.maxX, r.maxY - rad)),
            .curve(p(r.maxX, r.maxY - rad + k), p(r.maxX - rad + k, r.maxY), p(r.maxX - rad, r.maxY)),
            .line(p(r.minX + rad, r.maxY)),
            .curve(p(r.minX + rad - k, r.maxY), p(r.minX, r.maxY - rad + k), p(r.minX, r.maxY - rad)),
            .line(p(r.minX, r.minY + rad)),
            .curve(p(r.minX, r.minY + rad - k), p(r.minX + rad - k, r.minY), p(r.minX + rad, r.minY)),
            .close,
        ])
    }

    public static func circle(center c: BoardPoint, radius: Double) -> VectorPath {
        roundedRect(BoardRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius), radius: radius)
    }

    public static func polygon(_ points: [BoardPoint]) -> VectorPath {
        guard let first = points.first else { return VectorPath() }
        return VectorPath([.move(first)] + points.dropFirst().map { PathCommand.line($0) } + [.close])
    }
}

public enum Paint: Hashable, Sendable {
    case solid(RGBA)
    case linear(start: BoardPoint, end: BoardPoint, from: RGBA, to: RGBA)
    case radial(center: BoardPoint, radius: Double, from: RGBA, to: RGBA)

    func transformed(by t: Affine2D) -> Paint {
        switch self {
        case .solid: return self
        case .linear(let s, let e, let f, let to): return .linear(start: t.apply(s), end: t.apply(e), from: f, to: to)
        case .radial(let c, let r, let f, let to):
            return .radial(center: t.apply(c), radius: r * t.lengthScale, from: f, to: to)
        }
    }
}

public struct Stroke: Hashable, Sendable {
    public var color: RGBA
    public var width: Double
    public init(_ color: RGBA, width: Double) { self.color = color; self.width = width }
}

/// Drop shadow in screen space (dy > 0 is downwards); `blur` is the CoreGraphics blur.
public struct Shadow: Hashable, Sendable {
    public var dx: Double, dy: Double, blur: Double
    public var color: RGBA
    public init(dx: Double, dy: Double, blur: Double, color: RGBA) {
        self.dx = dx; self.dy = dy; self.blur = blur; self.color = color
    }
}

public struct VectorItem: Hashable, Sendable {
    public var path: VectorPath
    public var fill: Paint?
    public var stroke: Stroke?
    public var clip: VectorPath?
    public var shadow: Shadow?
    public init(
        path: VectorPath, fill: Paint? = nil, stroke: Stroke? = nil, clip: VectorPath? = nil, shadow: Shadow? = nil
    ) {
        self.path = path; self.fill = fill; self.stroke = stroke; self.clip = clip; self.shadow = shadow
    }

    public func transformed(by t: Affine2D) -> VectorItem {
        VectorItem(
            path: path.transformed(by: t), fill: fill?.transformed(by: t),
            stroke: stroke.map { Stroke($0.color, width: $0.width * t.lengthScale) },
            clip: clip?.transformed(by: t), shadow: shadow)
    }
}

public struct VectorScene: Hashable, Sendable {
    public var size: BoardSize
    public var items: [VectorItem]
    public init(size: BoardSize, items: [VectorItem]) { self.size = size; self.items = items }
}

// MARK: - Motifs

/// A traditional spade pip, always drawn with one uniform scale (width : height = `aspect`).
public enum SpadePip {
    public static let aspect: Double = 0.86

    /// Unit outline in a 0...aspect × 0...1 box.
    static let unit: [PathCommand] = {
        func p(_ x: Double, _ y: Double) -> BoardPoint { BoardPoint(x: x * aspect, y: y) }
        return [
            .move(p(0.5, 0)),
            .curve(p(0.60, 0.16), p(1.0, 0.33), p(1.0, 0.58)),
            .curve(p(1.0, 0.77), p(0.84, 0.86), p(0.70, 0.86)),
            .curve(p(0.62, 0.86), p(0.56, 0.83), p(0.53, 0.78)),
            .curve(p(0.55, 0.89), p(0.61, 0.96), p(0.70, 1.0)),
            .line(p(0.30, 1.0)),
            .curve(p(0.39, 0.96), p(0.45, 0.89), p(0.47, 0.78)),
            .curve(p(0.44, 0.83), p(0.38, 0.86), p(0.30, 0.86)),
            .curve(p(0.16, 0.86), p(0.0, 0.77), p(0.0, 0.58)),
            .curve(p(0.0, 0.33), p(0.40, 0.16), p(0.5, 0)),
            .close,
        ]
    }()

    /// The largest undistorted spade centred in `rect`.
    public static func path(in rect: BoardRect) -> VectorPath {
        let height = min(rect.height, rect.width / aspect)
        let width = height * aspect
        let t = Affine2D.scale(height).then(.translation(rect.midX - width / 2, rect.midY - height / 2))
        return VectorPath(unit).transformed(by: t)
    }
}

/// Neutral classic ornament for the card back: an eight-petal rosette inside a lozenge.
public enum Rosette {
    public static let gold = RGBA(0.96, 0.78, 0.20)
    public static let cream = RGBA(1.0, 0.97, 0.88)
    public static let navy = RGBA(0.04, 0.12, 0.42)

    /// `radius` is the petal length; the lozenge reaches 1.3 × radius vertically.
    public static func items(center c: BoardPoint, radius r: Double, lineWidth: Double) -> [VectorItem] {
        var items: [VectorItem] = []
        let lozenge = VectorPath.polygon([
            BoardPoint(x: c.x, y: c.y - r * 1.3), BoardPoint(x: c.x + r * 0.95, y: c.y),
            BoardPoint(x: c.x, y: c.y + r * 1.3), BoardPoint(x: c.x - r * 0.95, y: c.y),
        ])
        items.append(
            VectorItem(path: lozenge, fill: .solid(navy.withAlpha(0.35)), stroke: Stroke(gold, width: lineWidth)))
        for k in 0..<8 {
            let angle = Double(k) * Double.pi / 4
            let petal = petalPath(center: c, angle: angle, length: r * (k % 2 == 0 ? 0.92 : 0.7), halfWidth: r * 0.2)
            items.append(VectorItem(path: petal, fill: .solid(k % 2 == 0 ? gold : cream.withAlpha(0.9))))
        }
        items.append(
            VectorItem(
                path: .circle(center: c, radius: r * 0.2), fill: .solid(gold),
                stroke: Stroke(navy.withAlpha(0.6), width: lineWidth * 0.6)))
        items.append(VectorItem(path: .circle(center: c, radius: r * 0.08), fill: .solid(navy)))
        return items
    }

    static func petalPath(center c: BoardPoint, angle: Double, length l: Double, halfWidth hw: Double) -> VectorPath {
        let ux = VectorMath.cos(angle), uy = VectorMath.sin(angle)
        let nx = -uy, ny = ux
        func q(_ along: Double, _ across: Double) -> BoardPoint {
            BoardPoint(x: c.x + ux * along + nx * across, y: c.y + uy * along + ny * across)
        }
        return VectorPath([
            .move(q(0, 0)),
            .curve(q(l * 0.3, hw), q(l * 0.75, hw * 0.8), q(l, 0)),
            .curve(q(l * 0.75, -hw * 0.8), q(l * 0.3, -hw), q(0, 0)),
            .close,
        ])
    }
}

// MARK: - Card back

public enum CardBackArt {
    public static let white = RGBA(1, 1, 1)
    public static let border = RGBA(0.12, 0.12, 0.12)
    public static let blueLight = RGBA(0.20, 0.38, 0.86)
    public static let blueDark = RGBA(0.04, 0.15, 0.52)

    /// The blue back for a card of `size` (points). `lineScale` thickens hairlines for big renders
    /// such as the app icon. Same metrics as the face: corner radius 7 % of the width.
    public static func scene(size: BoardSize, lineScale: Double = 1) -> VectorScene {
        let w = size.width, h = size.height
        let radius = max(3, w * 0.07)
        let rim = max(2, w * 0.06)
        let inner = max(2, radius - rim / 2)
        let card = BoardRect(x: 0, y: 0, width: w, height: h)
        let field = BoardRect(x: rim, y: rim, width: w - 2 * rim, height: h - 2 * rim)
        let fieldPath = VectorPath.roundedRect(field, radius: inner)
        let hairline = 1.0 * lineScale

        var items: [VectorItem] = []
        items.append(VectorItem(path: .roundedRect(card, radius: radius), fill: .solid(white)))
        items.append(
            VectorItem(
                path: fieldPath,
                fill: .linear(
                    start: BoardPoint(x: field.minX, y: field.minY),
                    end: BoardPoint(x: field.maxX, y: field.maxY),
                    from: blueLight, to: blueDark)))
        items.append(
            VectorItem(
                path: lattice(in: field, spacing: max(4, w * 0.1)),
                stroke: Stroke(white.withAlpha(0.22), width: hairline),
                clip: fieldPath))
        let frameInset = max(2, w * 0.05) + hairline / 2
        let frame = BoardRect(
            x: field.minX + frameInset, y: field.minY + frameInset,
            width: field.width - 2 * frameInset, height: field.height - 2 * frameInset)
        items.append(
            VectorItem(
                path: .roundedRect(frame, radius: max(1, inner - 1)),
                stroke: Stroke(Rosette.gold.withAlpha(0.8), width: hairline)))
        items += Rosette.items(
            center: BoardPoint(x: w / 2, y: h / 2), radius: w * 0.2, lineWidth: max(1, w * 0.015) * lineScale)
        let half = hairline / 2
        items.append(
            VectorItem(
                path: .roundedRect(
                    BoardRect(x: half, y: half, width: w - hairline, height: h - hairline),
                    radius: max(0, radius - half)),
                stroke: Stroke(border, width: hairline)))
        return VectorScene(size: size, items: items)
    }

    /// Diagonal criss-cross lines covering `rect` (the caller clips them).
    public static func lattice(in rect: BoardRect, spacing: Double) -> VectorPath {
        var path = VectorPath()
        var offset = -rect.height
        while offset < rect.width + rect.height {
            path.commands += [
                .move(BoardPoint(x: rect.minX + offset, y: rect.minY)),
                .line(BoardPoint(x: rect.minX + offset + rect.height, y: rect.maxY)),
                .move(BoardPoint(x: rect.minX + offset + rect.height, y: rect.minY)),
                .line(BoardPoint(x: rect.minX + offset, y: rect.maxY)),
            ]
            offset += spacing
        }
        return path
    }
}

// MARK: - App icon

public enum AppIconArt {
    public static let size: Double = 1024

    /// Green felt tile with a blue card back and, in front, a white card with a large spade.
    public static func scene() -> VectorScene {
        var items: [VectorItem] = []
        let tile = BoardRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = VectorPath.roundedRect(tile, radius: 185)
        items.append(
            VectorItem(
                path: tilePath, fill: .solid(RGBA(0.0, 0.42, 0.06)),
                shadow: Shadow(dx: 0, dy: 10, blur: 24, color: RGBA(0, 0, 0, 0.35))))
        items.append(
            VectorItem(
                path: tilePath,
                fill: .radial(
                    center: BoardPoint(x: 470, y: 380), radius: 600,
                    from: RGBA(0.08, 0.62, 0.16), to: RGBA(0.0, 0.36, 0.05))))
        items.append(VectorItem(path: tilePath, stroke: Stroke(RGBA(0, 0.2, 0, 0.6), width: 6)))

        let cardSize = BoardSize(width: 400, height: 400 * 96 / 71)
        let shadow = Shadow(dx: 6, dy: 14, blur: 28, color: RGBA(0, 0, 0, 0.45))

        // Back card, tilted left.
        let back = placement(cardSize, center: BoardPoint(x: 430, y: 520), degrees: -13)
        items.append(cardShadow(cardSize, shadow).transformed(by: back))
        items += CardBackArt.scene(size: cardSize, lineScale: 3.5).items.map { $0.transformed(by: back) }

        // Front card: white face with a big spade and two corner pips.
        let front = placement(cardSize, center: BoardPoint(x: 598, y: 532), degrees: 9)
        let w = cardSize.width, h = cardSize.height
        let radius = w * 0.07
        var face: [VectorItem] = [cardShadow(cardSize, shadow)]
        face.append(
            VectorItem(
                path: .roundedRect(BoardRect(x: 0, y: 0, width: w, height: h), radius: radius),
                fill: .solid(RGBA(1, 1, 1))))
        let black = RGBA(0.06, 0.06, 0.06)
        face.append(
            VectorItem(
                path: SpadePip.path(in: BoardRect(x: w * 0.17, y: h * 0.2, width: w * 0.66, height: h * 0.6)),
                fill: .solid(black)))
        let corner = BoardRect(x: w * 0.07, y: h * 0.06, width: w * 0.13, height: w * 0.15)
        face.append(VectorItem(path: SpadePip.path(in: corner), fill: .solid(black)))
        let flip = Affine2D.rotation(degrees: 180).then(.translation(w, h))
        face.append(VectorItem(path: SpadePip.path(in: corner).transformed(by: flip), fill: .solid(black)))
        face.append(
            VectorItem(
                path: .roundedRect(BoardRect(x: 2.5, y: 2.5, width: w - 5, height: h - 5), radius: radius - 2.5),
                stroke: Stroke(RGBA(0.12, 0.12, 0.12), width: 5)))
        items += face.map { $0.transformed(by: front) }
        return VectorScene(size: BoardSize(width: size, height: size), items: items)
    }

    static func placement(_ card: BoardSize, center: BoardPoint, degrees: Double) -> Affine2D {
        Affine2D.translation(-card.width / 2, -card.height / 2)
            .then(.rotation(degrees: degrees))
            .then(.translation(center.x, center.y))
    }

    static func cardShadow(_ card: BoardSize, _ shadow: Shadow) -> VectorItem {
        VectorItem(
            path: .roundedRect(
                BoardRect(x: 0, y: 0, width: card.width, height: card.height), radius: card.width * 0.07),
            fill: .solid(RGBA(1, 1, 1)), shadow: shadow)
    }
}

// MARK: - SVG

extension VectorScene {
    /// Standalone SVG (used for Linux previews and tests; the app draws natively).
    public func svg() -> String {
        var defs: [String] = []
        var body: [String] = []
        func n(_ v: Double) -> String {
            let r = (v * 1000).rounded() / 1000
            return r == r.rounded() ? String(Int(r)) : String(r)
        }
        func d(_ path: VectorPath) -> String {
            path.commands.map { (c: PathCommand) -> String in
                switch c {
                case .move(let p): return "M\(n(p.x)) \(n(p.y))"
                case .line(let p): return "L\(n(p.x)) \(n(p.y))"
                case .curve(let a, let b, let p): return "C\(n(a.x)) \(n(a.y)) \(n(b.x)) \(n(b.y)) \(n(p.x)) \(n(p.y))"
                case .close: return "Z"
                }
            }.joined(separator: " ")
        }
        func rgb(_ c: RGBA) -> String {
            "rgb(\(Int((c.r * 255).rounded())),\(Int((c.g * 255).rounded())),\(Int((c.b * 255).rounded())))"
        }
        for (i, item) in items.enumerated() {
            var attributes: [String] = ["d=\"\(d(item.path))\""]
            if let clip = item.clip {
                defs.append("<clipPath id=\"c\(i)\"><path d=\"\(d(clip))\"/></clipPath>")
                attributes.append("clip-path=\"url(#c\(i))\"")
            }
            if let s = item.shadow {
                defs.append(
                    "<filter id=\"s\(i)\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\"><feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"\(n(s.blur / 2))\"/>"
                        + "<feOffset dx=\"\(n(s.dx))\" dy=\"\(n(s.dy))\" result=\"o\"/><feFlood flood-color=\"\(rgb(s.color))\" flood-opacity=\"\(n(s.color.a))\"/>"
                        + "<feComposite in2=\"o\" operator=\"in\"/><feMerge><feMergeNode/><feMergeNode in=\"SourceGraphic\"/></feMerge></filter>"
                )
                attributes.append("filter=\"url(#s\(i))\"")
            }
            switch item.fill {
            case .none: attributes.append("fill=\"none\"")
            case .solid(let c)?: attributes.append("fill=\"\(rgb(c))\" fill-opacity=\"\(n(c.a))\"")
            case .linear(let s, let e, let f, let t)?:
                defs.append(
                    "<linearGradient id=\"g\(i)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(n(s.x))\" y1=\"\(n(s.y))\" x2=\"\(n(e.x))\" y2=\"\(n(e.y))\">"
                        + "<stop offset=\"0\" stop-color=\"\(rgb(f))\" stop-opacity=\"\(n(f.a))\"/><stop offset=\"1\" stop-color=\"\(rgb(t))\" stop-opacity=\"\(n(t.a))\"/></linearGradient>"
                )
                attributes.append("fill=\"url(#g\(i))\"")
            case .radial(let c, let r, let f, let t)?:
                defs.append(
                    "<radialGradient id=\"g\(i)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(n(c.x))\" cy=\"\(n(c.y))\" r=\"\(n(r))\">"
                        + "<stop offset=\"0\" stop-color=\"\(rgb(f))\" stop-opacity=\"\(n(f.a))\"/><stop offset=\"1\" stop-color=\"\(rgb(t))\" stop-opacity=\"\(n(t.a))\"/></radialGradient>"
                )
                attributes.append("fill=\"url(#g\(i))\"")
            }
            if let s = item.stroke {
                attributes.append(
                    "stroke=\"\(rgb(s.color))\" stroke-opacity=\"\(n(s.color.a))\" stroke-width=\"\(n(s.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
                )
            }
            body.append("<path " + attributes.joined(separator: " ") + "/>")
        }
        return
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(size.width))\" height=\"\(n(size.height))\" viewBox=\"0 0 \(n(size.width)) \(n(size.height))\">\n"
            + "<defs>" + defs.joined() + "</defs>\n" + body.joined(separator: "\n") + "\n</svg>\n"
    }
}
