/// A bitmap's size in device pixels.
public struct PixelSize: Hashable, Sendable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// The bitmap that covers a view of `points` on a display with `scale` pixels per point
    /// (NSWindow.backingScaleFactor, SwiftUI's displayScale): each side rounded to whole pixels.
    /// Drawn at `scale`, one bitmap pixel lands on one screen pixel, so nothing is resampled.
    public init(points: BoardSize, scale: Double) {
        let s: Double = scale.isFinite && scale > 0 ? scale : 1
        self.init(
            width: PixelSize.whole(points.width * s),
            height: PixelSize.whole(points.height * s))
    }

    public var description: String { "\(width)×\(height) px" }

    /// Rounds to the nearest pixel; the 1e-6 keeps 40.5 × 2 = 80.99999 from becoming 80.
    static func whole(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 1 }
        return Int((value + 1e-6).rounded())
    }
}

/// How a Classic card face is laid out in its bitmap.
public enum ClassicCardRaster {
    /// The art's rectangle inside a card bitmap of `pixels`: the art (width / height = `artAspect`)
    /// fitted with one uniform scale and centred, like `.aspectRatio(contentMode: .fit)`. The rect is
    /// symmetric, so it is the same whether y runs down (SwiftUI) or up (CoreGraphics).
    public static func artRect(in pixels: PixelSize, artAspect: Double = ClassicCardArt.artAspect) -> BoardRect {
        let w: Double = Double(pixels.width)
        let h: Double = Double(pixels.height)
        guard artAspect.isFinite, artAspect > 0 else { return BoardRect(x: 0, y: 0, width: w, height: h) }
        if w / h > artAspect {
            let artWidth: Double = h * artAspect
            return BoardRect(x: (w - artWidth) / 2, y: 0, width: artWidth, height: h)
        }
        let artHeight: Double = w / artAspect
        return BoardRect(x: 0, y: (h - artHeight) / 2, width: w, height: artHeight)
    }
}

/// Card face bitmaps, each rendered once per (card, pixel size) and reused for every frame after.
///
/// A request at a pixel size the cache has not seen means the card size or the display scale
/// changed (the window was resized or moved to another display). The cache keeps the bitmaps of
/// the `sizeCapacity` most recently used sizes, so the board and the small Settings previews can
/// live side by side, and drops a size, with every bitmap rendered at it, once it falls out of
/// that window. Generic over the bitmap type so the policy is testable without CoreGraphics.
public struct CardBitmapCache<Bitmap> {
    public struct Key: Hashable, Sendable {
        public let name: String
        public let pixels: PixelSize

        public init(name: String, pixels: PixelSize) {
            self.name = name
            self.pixels = pixels
        }
    }

    public let sizeCapacity: Int
    private var bitmaps: [Key: Bitmap] = [:]
    /// Pixel sizes in use, most recently used first; never longer than `sizeCapacity`.
    public private(set) var recentSizes: [PixelSize] = []
    /// How many times `render` was called (a cache miss); lets tests and logs count the work.
    public private(set) var renderCount: Int = 0

    public init(sizeCapacity: Int = 4) {
        self.sizeCapacity = max(1, sizeCapacity)
    }

    /// The bitmap of `name` at `pixels`, rendering it with `render` the first time. A nil render
    /// (missing or broken file) is not stored, so the caller decides how to remember failures.
    public mutating func bitmap(name: String, pixels: PixelSize, render: (String, PixelSize) -> Bitmap?) -> Bitmap? {
        touch(pixels)
        let key: Key = Key(name: name, pixels: pixels)
        if let cached: Bitmap = bitmaps[key] { return cached }
        renderCount += 1
        guard let fresh: Bitmap = render(name, pixels) else { return nil }
        bitmaps[key] = fresh
        return fresh
    }

    public func contains(name: String, pixels: PixelSize) -> Bool {
        bitmaps[Key(name: name, pixels: pixels)] != nil
    }

    /// Number of stored bitmaps.
    public var count: Int { bitmaps.count }

    public mutating func removeAll() {
        bitmaps.removeAll()
        recentSizes.removeAll()
    }

    /// Marks `pixels` as most recently used and evicts the sizes beyond the capacity.
    private mutating func touch(_ pixels: PixelSize) {
        if recentSizes.first == pixels { return }
        recentSizes.removeAll { (size: PixelSize) -> Bool in size == pixels }
        recentSizes.insert(pixels, at: 0)
        guard recentSizes.count > sizeCapacity else { return }
        let evicted: Set<PixelSize> = Set(recentSizes[sizeCapacity...])
        recentSizes.removeLast(recentSizes.count - sizeCapacity)
        bitmaps = bitmaps.filter { (entry: (key: Key, value: Bitmap)) -> Bool in !evicted.contains(entry.key.pixels) }
    }
}
