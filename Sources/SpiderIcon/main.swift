// Renders the app icon (1024×1024 PNG) with CoreGraphics: two fanned cards on green felt, the
// front one carrying the spider emblem. scripts/package.sh turns it into AppIcon.icns.
// Usage: SpiderIcon <output.png>
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

let arguments: [String] = CommandLine.arguments
guard arguments.count == 2 else { fail("usage: SpiderIcon <output.png>", code: 2) }
let outputURL: URL = URL(fileURLWithPath: arguments[1])

#if canImport(CoreGraphics) && canImport(ImageIO)
enum IconRenderer {
    static let size: Int = 1024

    static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func render(to url: URL) throws {
        guard let space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx: CGContext = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw IconError.context }

        // Work top-left/y-down like the rest of the app (SpiderGlyph geometry).
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)

        // macOS icon grid: 824 pt rounded square centred in 1024.
        let tile: CGRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath: CGPath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: srgb(0, 0, 0, 0.35))
        ctx.addPath(tilePath)
        ctx.setFillColor(srgb(0.0, 0.42, 0.06))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()
        let felt: CGGradient = CGGradient(colorsSpace: space,
                                          colors: [srgb(0.08, 0.62, 0.16), srgb(0.0, 0.36, 0.05)] as CFArray,
                                          locations: [0, 1])!
        ctx.drawRadialGradient(felt, startCenter: CGPoint(x: 470, y: 380), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 512), endRadius: 600,
                               options: CGGradientDrawingOptions.drawsAfterEndLocation)
        ctx.restoreGState()
        ctx.addPath(tilePath)
        ctx.setStrokeColor(srgb(0, 0.2, 0, 0.6))
        ctx.setLineWidth(6)
        ctx.strokePath()

        let cardWidth: CGFloat = 400
        let cardSize: CGSize = CGSize(width: cardWidth, height: cardWidth * 96 / 71)
        drawCard(ctx, space: space, centre: CGPoint(x: 430, y: 520), size: cardSize, degrees: -13, faceUp: false)
        drawCard(ctx, space: space, centre: CGPoint(x: 598, y: 532), size: cardSize, degrees: 9, faceUp: true)

        guard let image: CGImage = ctx.makeImage(),
              let destination: CGImageDestination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw IconError.encode }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconError.encode }
    }

    static func drawCard(_ ctx: CGContext, space: CGColorSpace, centre: CGPoint, size: CGSize, degrees: CGFloat, faceUp: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: degrees * CGFloat.pi / 180)
        let rect: CGRect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let radius: CGFloat = size.width * 0.07
        let outline: CGPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 6, height: -14), blur: 28, color: srgb(0, 0, 0, 0.45))
        ctx.addPath(outline)
        ctx.setFillColor(srgb(1, 1, 1))
        ctx.fillPath()
        ctx.restoreGState()

        if faceUp {
            drawSpider(ctx, in: rect.insetBy(dx: size.width * 0.12, dy: size.height * 0.2), colour: srgb(0.06, 0.06, 0.06))
            let corners: [CGPoint] = [CGPoint(x: rect.minX + size.width * 0.13, y: rect.minY + size.height * 0.11),
                                      CGPoint(x: rect.maxX - size.width * 0.13, y: rect.maxY - size.height * 0.11)]
            for corner in corners {
                drawDiamond(ctx, centre: corner, width: size.width * 0.1)
            }
        } else {
            let rim: CGFloat = size.width * 0.06
            let field: CGRect = rect.insetBy(dx: rim, dy: rim)
            let fieldPath: CGPath = CGPath(roundedRect: field, cornerWidth: radius * 0.6, cornerHeight: radius * 0.6, transform: nil)
            ctx.saveGState()
            ctx.addPath(fieldPath)
            ctx.clip()
            let blue: CGGradient = CGGradient(colorsSpace: space,
                                              colors: [srgb(0.20, 0.38, 0.86), srgb(0.04, 0.15, 0.52)] as CFArray,
                                              locations: [0, 1])!
            ctx.drawLinearGradient(blue, start: CGPoint(x: field.minX, y: field.minY),
                                   end: CGPoint(x: field.maxX, y: field.maxY), options: [])
            ctx.setStrokeColor(srgb(1, 1, 1, 0.22))
            ctx.setLineWidth(3)
            var offset: CGFloat = -field.height
            while offset < field.width + field.height {
                ctx.move(to: CGPoint(x: field.minX + offset, y: field.minY))
                ctx.addLine(to: CGPoint(x: field.minX + offset + field.height, y: field.maxY))
                ctx.move(to: CGPoint(x: field.minX + offset + field.height, y: field.minY))
                ctx.addLine(to: CGPoint(x: field.minX + offset, y: field.maxY))
                offset += size.width * 0.1
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(CGPath(roundedRect: field.insetBy(dx: size.width * 0.05, dy: size.width * 0.05),
                               cornerWidth: radius * 0.4, cornerHeight: radius * 0.4, transform: nil))
            ctx.setStrokeColor(srgb(0.96, 0.78, 0.2, 0.85))
            ctx.setLineWidth(4)
            ctx.strokePath()
            let emblem: CGFloat = size.width * 0.5
            drawSpider(ctx, in: CGRect(x: -emblem / 2, y: -emblem / 2, width: emblem, height: emblem),
                       colour: srgb(1, 1, 1, 0.9))
        }

        ctx.addPath(outline)
        ctx.setStrokeColor(srgb(0.12, 0.12, 0.12))
        ctx.setLineWidth(5)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func drawSpider(_ ctx: CGContext, in rect: CGRect, colour: CGColor) {
        let box: BoardRect = BoardRect(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
        ctx.saveGState()
        ctx.setStrokeColor(colour)
        ctx.setFillColor(colour)
        ctx.setLineWidth(CGFloat(SpiderGlyph.legWidth(in: box)))
        ctx.setLineCap(CGLineCap.round)
        ctx.setLineJoin(CGLineJoin.round)
        for leg in SpiderGlyph.legs(in: box) {
            guard let first: BoardPoint = leg.first else { continue }
            ctx.move(to: CGPoint(x: first.x, y: first.y))
            for point in leg.dropFirst() { ctx.addLine(to: CGPoint(x: point.x, y: point.y)) }
        }
        ctx.strokePath()
        let parts: (abdomen: BoardRect, head: BoardRect) = SpiderGlyph.body(in: box)
        for part in [parts.abdomen, parts.head] {
            ctx.fillEllipse(in: CGRect(x: part.x, y: part.y, width: part.width, height: part.height))
        }
        ctx.restoreGState()
    }

    static func drawDiamond(_ ctx: CGContext, centre: CGPoint, width: CGFloat) {
        let h: CGFloat = width * 1.3
        ctx.move(to: CGPoint(x: centre.x, y: centre.y - h / 2))
        ctx.addLine(to: CGPoint(x: centre.x + width / 2, y: centre.y))
        ctx.addLine(to: CGPoint(x: centre.x, y: centre.y + h / 2))
        ctx.addLine(to: CGPoint(x: centre.x - width / 2, y: centre.y))
        ctx.closePath()
        ctx.setFillColor(srgb(0.85, 0, 0))
        ctx.fillPath()
    }
}

enum IconError: Error {
    case context
    case encode
}

do {
    try IconRenderer.render(to: outputURL)
    print(outputURL.path)
} catch {
    fail("SpiderIcon: could not render the icon (\(error))", code: 1)
}
#else
// No CoreGraphics (Linux CI): write a 1×1 placeholder PNG so packaging scripts can be dry-run.
let placeholder: String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg=="
do {
    try Data(base64Encoded: placeholder)!.write(to: outputURL)
    print(outputURL.path + " (placeholder: CoreGraphics unavailable)")
} catch {
    fail("SpiderIcon: \(error)", code: 1)
}
#endif
