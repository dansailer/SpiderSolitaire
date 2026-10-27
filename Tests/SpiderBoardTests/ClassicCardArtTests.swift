import Foundation
import XCTest
import SpiderCore
@testable import SpiderBoard

final class ClassicCardArtTests: XCTestCase {
    private var cardsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SpiderSolitaire/Resources/Cards")
    }

    func testAssetNames() {
        XCTAssertEqual(ClassicCardArt.assetName(rank: .king, suit: .spades), "spades_king")
        XCTAssertEqual(ClassicCardArt.assetName(rank: .queen, suit: .hearts), "hearts_queen")
        XCTAssertEqual(ClassicCardArt.assetName(rank: .jack, suit: .diamonds), "diamonds_jack")
        XCTAssertEqual(ClassicCardArt.assetName(rank: .ace, suit: .clubs), "clubs_ace")
        XCTAssertEqual(ClassicCardArt.assetName(rank: .ten, suit: .hearts), "hearts_10")
        XCTAssertEqual(ClassicCardArt.assetName(rank: .two, suit: .spades), "spades_2")
        XCTAssertEqual(ClassicCardArt.fileName(rank: .seven, suit: .clubs), "clubs_7.png")
        let card = Card(id: 3, suit: .diamonds, rank: .queen, isFaceUp: true)
        XCTAssertEqual(ClassicCardArt.assetName(for: card), "diamonds_queen")
    }

    func testAllFiftyTwoNamesAreUnique() {
        let names = ClassicCardArt.allAssetNames
        XCTAssertEqual(names.count, 52)
        XCTAssertEqual(Set(names).count, 52)
        XCTAssertEqual(names.first, "spades_ace")
        XCTAssertEqual(names.last, "clubs_king")
    }

    /// Every mapped name has a 240 × 324 PNG in the app's resources, and nothing else is there.
    func testEveryCardHasAnImageOfTheRightSize() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: cardsDirectory.path)
        let pngs = Set(files.filter { $0.hasSuffix(".png") })
        XCTAssertEqual(pngs, Set(ClassicCardArt.allAssetNames.map { $0 + ".png" }))
        for name in ClassicCardArt.allAssetNames {
            let data = try Data(contentsOf: cardsDirectory.appendingPathComponent(name + ".png"))
            XCTAssertGreaterThan(data.count, 24, name)
            let bytes = [UInt8](data.prefix(24))
            XCTAssertEqual(Array(bytes[0..<8]), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "\(name) is not a PNG")
            let width = bytes[16..<20].reduce(0) { ($0 << 8) | Int($1) }
            let height = bytes[20..<24].reduce(0) { ($0 << 8) | Int($1) }
            XCTAssertEqual(width, ClassicCardArt.pixelWidth, name)
            XCTAssertEqual(height, ClassicCardArt.pixelHeight, name)
            XCTAssertLessThan(data.count, 60_000, "\(name) should stay small")
        }
        // Same proportions as the on-screen card (71 × 96) within 0.2 %.
        let aspect = Double(ClassicCardArt.pixelHeight) / Double(ClassicCardArt.pixelWidth)
        XCTAssertEqual(aspect, BoardLayout.cardAspect, accuracy: BoardLayout.cardAspect * 0.002)
    }

    /// CREDITS.md lists a source and a CC0 / public-domain licence for every image.
    func testCreditsCoverEveryImageWithACleanLicence() throws {
        let credits = try String(contentsOf: cardsDirectory.appendingPathComponent("CREDITS.md"), encoding: .utf8)
        let rows = credits.split(separator: "\n").filter { $0.hasPrefix("| `") }
        for name in ClassicCardArt.allAssetNames {
            let mine = rows.filter { $0.hasPrefix("| `\(name).png` |") }
            XCTAssertFalse(mine.isEmpty, "\(name) missing from CREDITS.md")
            for row in mine {
                let columns = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                XCTAssertTrue(columns[1].contains("https://commons.wikimedia.org/wiki/File:"), String(row))
                XCTAssertTrue(["CC0 1.0", "Public domain"].contains(columns[3]), String(row))
            }
        }
    }

    func testBundleCandidatesPreferContentsResources() {
        let candidates = ClassicCardArt.bundleCandidates(
            resourcePath: "/Applications/Spider Solitaire.app/Contents/Resources",
            mainBundlePath: "/Applications/Spider Solitaire.app",
            executablePath: "/Applications/Spider Solitaire.app/Contents/MacOS/SpiderSolitaire")
        XCTAssertEqual(candidates.first, "/Applications/Spider Solitaire.app/Contents/Resources/SpiderSolitaire_SpiderSolitaire.bundle")
        XCTAssertTrue(candidates.contains("/Applications/Spider Solitaire.app/SpiderSolitaire_SpiderSolitaire.bundle"))
        XCTAssertTrue(candidates.contains("/Applications/Spider Solitaire.app/Contents/MacOS/SpiderSolitaire_SpiderSolitaire.bundle"))
        XCTAssertEqual(Set(candidates).count, candidates.count)
    }

    func testBundleCandidatesForSwiftRun() {
        // `swift run`: no .app, Bundle.main is the build folder, the bundle sits next to the binary.
        let candidates = ClassicCardArt.bundleCandidates(
            resourcePath: nil,
            mainBundlePath: "/repo/.build/arm64-apple-macosx/debug",
            executablePath: "/repo/.build/arm64-apple-macosx/debug/SpiderSolitaire")
        XCTAssertEqual(candidates, [
            "/repo/.build/arm64-apple-macosx/debug/SpiderSolitaire_SpiderSolitaire.bundle",
            "/repo/.build/arm64-apple-macosx/debug/SpiderSolitaire_SpiderSolitaire.resources",
        ])
    }

    func testImagePathCandidatesCoverBothBundleLayouts() {
        XCTAssertEqual(ClassicCardArt.imagePathCandidates(bundlePath: "/b/R.bundle/", assetName: "hearts_king"), [
            "/b/R.bundle/Contents/Resources/Cards/hearts_king.png",
            "/b/R.bundle/Cards/hearts_king.png",
        ])
        XCTAssertEqual(ClassicCardArt.parentDirectory(of: "/a/b/c"), "/a/b")
        XCTAssertEqual(ClassicCardArt.parentDirectory(of: "/c"), "/")
        XCTAssertEqual(ClassicCardArt.parentDirectory(of: "c"), ".")
    }
}
