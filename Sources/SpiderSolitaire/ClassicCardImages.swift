#if canImport(AppKit)
import AppKit
import SpiderBoard
import SpiderCore

/// One Classic face, rendered for one card size on one display: `image` has exactly the card's
/// size in device pixels, so drawing it at `scale` maps one bitmap pixel to one screen pixel.
struct ClassicCardBitmap {
    let image: CGImage
    let scale: CGFloat
    let pixels: PixelSize

    /// The bitmap's size in points (the card size, to within half a pixel).
    var pointSize: CGSize {
        CGSize(width: CGFloat(pixels.width) / scale, height: CGFloat(pixels.height) / scale)
    }
}

/// Loads the Classic card face PDFs from the app's resource bundle and renders each one once per
/// (card, pixel size) into a bitmap. CardView then only draws cached bitmaps, so dragging cards
/// and the win animation never touch the vector art; a new card size or display scale (window
/// resize, another display) renders that size once and old sizes age out (`CardBitmapCache`).
///
/// Deliberately not `Bundle.module`: SwiftPM's generated accessor looks next to the executable's
/// bundle root (`X.app/SpiderSolitaire_SpiderSolitaire.bundle`) and then the absolute build folder,
/// and calls `fatalError` if neither exists. A signed .app keeps the bundle in Contents/Resources,
/// so we search there first and simply fall back to the code-drawn faces when nothing is found.
final class ClassicCardImages: @unchecked Sendable {
    static let shared: ClassicCardImages = ClassicCardImages()

    private let lock: NSLock = NSLock()
    private var documents: [String: CGPDFDocument] = [:]
    private var missing: Set<String> = []
    private var bitmaps: CardBitmapCache<CGImage> = CardBitmapCache<CGImage>()
    private let bundlePaths: [String]

    init() {
        let candidates: [String] = ClassicCardArt.bundleCandidates(
            resourcePath: Bundle.main.resourceURL?.path,
            mainBundlePath: Bundle.main.bundleURL.path,
            executablePath: Bundle.main.executableURL?.resolvingSymlinksInPath().path)
        var isDirectory: ObjCBool = false
        bundlePaths = candidates.filter { (path: String) -> Bool in
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The face of `card` as a bitmap for a card of `size` points on a display with `scale` pixels
    /// per point, or nil (then CardView draws the simple face).
    func bitmap(for card: Card, size: CGSize, scale: CGFloat) -> ClassicCardBitmap? {
        let name: String = ClassicCardArt.assetName(for: card)
        let pixels: PixelSize = PixelSize(
            points: BoardSize(width: Double(size.width), height: Double(size.height)), scale: Double(scale))
        lock.lock()
        defer { lock.unlock() }
        guard let document: CGPDFDocument = document(named: name) else { return nil }
        let image: CGImage? = bitmaps.bitmap(name: name, pixels: pixels) { (_: String, pixels: PixelSize) in
            ClassicCardRenderer.render(document, pixels: pixels)
        }
        guard let image else { return nil }
        return ClassicCardBitmap(image: image, scale: scale, pixels: pixels)
    }

    /// Caller holds `lock`.
    private func document(named name: String) -> CGPDFDocument? {
        if let cached: CGPDFDocument = documents[name] { return cached }
        if missing.contains(name) { return nil }
        for bundlePath in bundlePaths {
            for path in ClassicCardArt.imagePathCandidates(bundlePath: bundlePath, assetName: name) {
                if let document: CGPDFDocument = CGPDFDocument(URL(fileURLWithPath: path) as CFURL),
                    document.numberOfPages >= 1
                {
                    documents[name] = document
                    return document
                }
            }
        }
        missing.insert(name)
        return nil
    }
}
#endif
