// Renders artwork described in SpiderBoard/VectorArt.swift.
//   SpiderIcon <out.png>              app icon, 1024 × 1024 PNG (CoreGraphics, macOS only)
//   SpiderIcon <out.svg>              app icon as SVG (any platform; used for Linux previews)
//   SpiderIcon --card-back <out.svg>  card back at the largest in-app size (120 × 162 pt)
// scripts/package.sh turns the PNG into AppIcon.icns.
import Foundation
import SpiderBoard
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var arguments: [String] = Array(CommandLine.arguments.dropFirst())
var cardBack: Bool = false
if arguments.first == "--card-back" {
    cardBack = true
    arguments.removeFirst()
}
guard arguments.count == 1 else { fail("usage: SpiderIcon [--card-back] <output.png|output.svg>", code: 2) }
let outputURL: URL = URL(fileURLWithPath: arguments[0])
let scene: VectorScene = cardBack
    ? CardBackArt.scene(size: BoardSize(width: BoardLayout.maxCardWidth, height: BoardLayout.maxCardWidth * BoardLayout.cardAspect))
    : AppIconArt.scene()

if outputURL.pathExtension.lowercased() == "svg" {
    do {
        try Data(scene.svg().utf8).write(to: outputURL)
        print(outputURL.path)
        exit(0)
    } catch {
        fail("SpiderIcon: \(error)", code: 1)
    }
}

#if canImport(CoreGraphics) && canImport(ImageIO)
enum SceneRenderer {
    static func color(_ c: RGBA) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }

    static func point(_ p: BoardPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    static func path(_ vector: VectorPath) -> CGPath {
        let path: CGMutablePath = CGMutablePath()
        for command in vector.commands {
            switch command {
            case .move(let p): path.move(to: point(p))
            case .line(let p): path.addLine(to: point(p))
            case .curve(let c1, let c2, let p): path.addCurve(to: point(p), control1: point(c1), control2: point(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    static func gradient(_ space: CGColorSpace, _ from: RGBA, _ to: RGBA) -> CGGradient? {
        CGGradient(colorsSpace: space, colors: [color(from), color(to)] as CFArray, locations: [0, 1])
    }

    static func render(_ scene: VectorScene, scale: Double, to url: URL) throws {
        let width: Int = Int(scene.size.width * scale)
        let height: Int = Int(scene.size.height * scale)
        guard let space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx: CGContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RenderError.context }
        // Top-left origin, y down, like the scene. Shadows ignore the CTM, hence -dy below.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))

        for item in scene.items {
            ctx.saveGState()
            if let clip: VectorPath = item.clip {
                ctx.addPath(path(clip))
                ctx.clip()
            }
            if let s: SpiderBoard.Shadow = item.shadow {
                ctx.setShadow(offset: CGSize(width: s.dx * scale, height: -s.dy * scale), blur: CGFloat(s.blur * scale), color: color(s.color))
            }
            let shape: CGPath = path(item.path)
            switch item.fill {
            case .none:
                break
            case .solid(let c)?:
                ctx.addPath(shape)
                ctx.setFillColor(color(c))
                ctx.fillPath()
            case .linear(let start, let end, let from, let to)?:
                ctx.saveGState()
                ctx.addPath(shape)
                ctx.clip()
                if let g: CGGradient = gradient(space, from, to) {
                    ctx.drawLinearGradient(g, start: point(start), end: point(end),
                                           options: [CGGradientDrawingOptions.drawsBeforeStartLocation, CGGradientDrawingOptions.drawsAfterEndLocation])
                }
                ctx.restoreGState()
            case .radial(let center, let radius, let from, let to)?:
                ctx.saveGState()
                ctx.addPath(shape)
                ctx.clip()
                if let g: CGGradient = gradient(space, from, to) {
                    ctx.drawRadialGradient(g, startCenter: point(center), startRadius: 0, endCenter: point(center),
                                           endRadius: CGFloat(radius), options: CGGradientDrawingOptions.drawsAfterEndLocation)
                }
                ctx.restoreGState()
            }
            if let stroke: SpiderBoard.Stroke = item.stroke {
                ctx.addPath(shape)
                ctx.setStrokeColor(color(stroke.color))
                ctx.setLineWidth(CGFloat(stroke.width))
                ctx.setLineCap(CGLineCap.round)
                ctx.setLineJoin(CGLineJoin.round)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        guard let image: CGImage = ctx.makeImage(),
              let destination: CGImageDestination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw RenderError.encode }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.encode }
    }
}

enum RenderError: Error {
    case context
    case encode
}

do {
    try SceneRenderer.render(scene, scale: cardBack ? 2 : 1, to: outputURL)
    print(outputURL.path)
} catch {
    fail("SpiderIcon: could not render (\(error))", code: 1)
}
#else
// No CoreGraphics (Linux): write a 1×1 placeholder PNG so package.sh can be dry-run. Use an .svg
// output path for a real preview.
let placeholder: String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg=="
do {
    try Data(base64Encoded: placeholder)!.write(to: outputURL)
    print(outputURL.path + " (placeholder: CoreGraphics unavailable; pass an .svg path for a preview)")
} catch {
    fail("SpiderIcon: \(error)", code: 1)
}
#endif
