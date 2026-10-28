import SpiderCore
import XCTest

@testable import SpiderBoard

final class CardBitmapCacheTests: XCTestCase {
    // MARK: Pixel size

    func testPixelSizeIsCardPointsTimesBackingScale() {
        // Largest card (120 × 162.25 pt, 71:96) on Retina: 240 × 325 px (324.5 rounds up).
        let largest = BoardSize(
            width: BoardLayout.maxCardWidth, height: BoardLayout.maxCardWidth * BoardLayout.cardAspect)
        XCTAssertEqual(PixelSize(points: largest, scale: 2), PixelSize(width: 240, height: 325))
        XCTAssertEqual(PixelSize(points: largest, scale: 1), PixelSize(width: 120, height: 162))
        XCTAssertEqual(
            PixelSize(points: BoardSize(width: 54, height: 73), scale: 2), PixelSize(width: 108, height: 146))
        XCTAssertEqual(
            PixelSize(points: BoardSize(width: 54, height: 73), scale: 3), PixelSize(width: 162, height: 219))
    }

    func testPixelSizeRoundsFractionalCardsToWholePixels() {
        XCTAssertEqual(
            PixelSize(points: BoardSize(width: 87.3, height: 118.03), scale: 2), PixelSize(width: 175, height: 236))
        XCTAssertEqual(
            PixelSize(points: BoardSize(width: 40.25, height: 54.4), scale: 1), PixelSize(width: 40, height: 54))
        // 40.5 × 2 is 81 exactly, even when the multiplication lands a hair below it.
        XCTAssertEqual(PixelSize(points: BoardSize(width: 40.499_999_9, height: 10), scale: 2).width, 81)
        XCTAssertEqual(
            PixelSize(points: BoardSize(width: 60, height: 80), scale: 1.5), PixelSize(width: 90, height: 120))
    }

    func testPixelSizeIsNeverEmpty() {
        XCTAssertEqual(PixelSize(points: BoardSize(width: 0, height: 0), scale: 2), PixelSize(width: 1, height: 1))
        XCTAssertEqual(PixelSize(points: BoardSize(width: 10, height: 10), scale: 0), PixelSize(width: 10, height: 10))
        XCTAssertEqual(
            PixelSize(points: BoardSize(width: 10, height: 10), scale: .nan), PixelSize(width: 10, height: 10))
        XCTAssertEqual(PixelSize(width: -3, height: 0), PixelSize(width: 1, height: 1))
    }

    // MARK: Art placement

    /// The 2:3 art fills the card's height and is centred across its width, like aspect-fit.
    func testArtRectFitsTheArtCentred() {
        let rect = ClassicCardRaster.artRect(in: PixelSize(width: 240, height: 324))
        XCTAssertEqual(rect.height, 324, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 216, accuracy: 1e-9)
        XCTAssertEqual(rect.x, 12, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.width / rect.height, ClassicCardArt.artAspect, accuracy: 1e-9)
        // A card wider than tall would letterbox vertically instead.
        let wide = ClassicCardRaster.artRect(in: PixelSize(width: 300, height: 300), artAspect: 2)
        XCTAssertEqual(wide, BoardRect(x: 0, y: 75, width: 300, height: 150))
    }

    // MARK: Cache policy

    private struct Bitmap: Equatable {
        let name: String
        let pixels: PixelSize
    }

    private func fetch(_ cache: inout CardBitmapCache<Bitmap>, _ name: String, _ pixels: PixelSize) -> Bitmap? {
        cache.bitmap(name: name, pixels: pixels) { (name: String, pixels: PixelSize) in
            Bitmap(name: name, pixels: pixels)
        }
    }

    private let board = PixelSize(width: 240, height: 324)
    private let preview = PixelSize(width: 108, height: 146)

    /// The vectors are rendered once per card and size; every later frame reuses the bitmap.
    func testEachCardRendersOncePerPixelSize() {
        var cache = CardBitmapCache<Bitmap>()
        for _ in 0..<100 {
            XCTAssertEqual(fetch(&cache, "spades_king", board), Bitmap(name: "spades_king", pixels: board))
            _ = fetch(&cache, "hearts_7", board)
        }
        XCTAssertEqual(cache.renderCount, 2)
        XCTAssertEqual(cache.count, 2)
        XCTAssertTrue(cache.contains(name: "spades_king", pixels: board))
        XCTAssertFalse(cache.contains(name: "spades_king", pixels: preview))
    }

    /// Resizing the window (or moving it to a display with another backing scale) changes the pixel
    /// size: the card is rendered again at the new size instead of scaling the old bitmap.
    func testANewSizeOrScaleRendersAgain() {
        var cache = CardBitmapCache<Bitmap>()
        let card = BoardSize(width: 100, height: 135)
        _ = fetch(&cache, "clubs_queen", PixelSize(points: card, scale: 2))
        let movedToNonRetina = fetch(&cache, "clubs_queen", PixelSize(points: card, scale: 1))
        XCTAssertEqual(movedToNonRetina?.pixels, PixelSize(width: 100, height: 135))
        let resized = fetch(&cache, "clubs_queen", PixelSize(points: BoardSize(width: 90, height: 121.5), scale: 1))
        XCTAssertEqual(resized?.pixels, PixelSize(width: 90, height: 122))
        XCTAssertEqual(cache.renderCount, 3)
    }

    /// Only the most recently used sizes stay; older sizes are dropped with all their bitmaps.
    func testOldSizesAreEvicted() {
        var cache = CardBitmapCache<Bitmap>(sizeCapacity: 2)
        _ = fetch(&cache, "a", board)
        _ = fetch(&cache, "b", board)
        _ = fetch(&cache, "a", preview)
        XCTAssertEqual(cache.recentSizes, [preview, board])
        XCTAssertEqual(cache.count, 3)
        // A live resize walks through new sizes: the oldest goes, the board's last size is kept.
        let resized = PixelSize(width: 230, height: 311)
        _ = fetch(&cache, "a", resized)
        XCTAssertEqual(cache.recentSizes, [resized, preview])
        XCTAssertFalse(cache.contains(name: "a", pixels: board))
        XCTAssertFalse(cache.contains(name: "b", pixels: board))
        XCTAssertTrue(cache.contains(name: "a", pixels: preview))
        XCTAssertEqual(cache.count, 2)
    }

    /// Using a size again moves it to the front, so the Settings preview and the board can take
    /// turns without re-rendering either.
    func testUsingASizeKeepsItAlive() {
        var cache = CardBitmapCache<Bitmap>(sizeCapacity: 2)
        _ = fetch(&cache, "a", board)
        _ = fetch(&cache, "a", preview)
        _ = fetch(&cache, "a", board)
        _ = fetch(&cache, "a", PixelSize(width: 50, height: 50))
        XCTAssertTrue(cache.contains(name: "a", pixels: board))
        XCTAssertFalse(cache.contains(name: "a", pixels: preview))
        XCTAssertEqual(cache.renderCount, 3)
    }

    func testFailedRendersAreNotStored() {
        var cache = CardBitmapCache<Bitmap>()
        XCTAssertNil(cache.bitmap(name: "missing", pixels: board) { (_: String, _: PixelSize) -> Bitmap? in nil })
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(fetch(&cache, "missing", board), Bitmap(name: "missing", pixels: board))
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.recentSizes, [])
    }
}
