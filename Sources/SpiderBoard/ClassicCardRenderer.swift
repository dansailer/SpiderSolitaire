#if canImport(CoreGraphics)
import CoreGraphics

/// Rasterises a Classic card face PDF (CoreGraphics, macOS only). The app calls this once per
/// (card, pixel size) through `CardBitmapCache`; nothing draws the vectors per frame.
public enum ClassicCardRenderer {
    /// Draws page 1 of `document` into a transparent sRGB bitmap of exactly `pixels`, the art fitted
    /// with one uniform scale and centred (`ClassicCardRaster.artRect`).
    public static func render(_ document: CGPDFDocument, pixels: PixelSize) -> CGImage? {
        guard let page: CGPDFPage = document.page(at: 1),
            let space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context: CGContext = CGContext(
                data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let box: CGRect = page.getBoxRect(CGPDFBox.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let art: BoardRect = ClassicCardRaster.artRect(in: pixels, artAspect: Double(box.width / box.height))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = CGInterpolationQuality.high
        context.translateBy(x: CGFloat(art.x), y: CGFloat(art.y))
        context.scaleBy(x: CGFloat(art.width) / box.width, y: CGFloat(art.height) / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }
}
#endif
