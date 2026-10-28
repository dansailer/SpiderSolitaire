import Foundation
import SpiderCore
import XCTest

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
        XCTAssertEqual(ClassicCardArt.fileName(rank: .seven, suit: .clubs), "clubs_7.pdf")
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

    private func pdfData(_ name: String) throws -> Data {
        try Data(contentsOf: cardsDirectory.appendingPathComponent(name + ".pdf"))
    }

    /// Every mapped name has a PDF in the app's resources, and nothing else is there (no PNGs).
    func testEveryCardHasAVectorPDF() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: cardsDirectory.path)
        XCTAssertEqual(
            Set(files.filter { $0.hasSuffix(".pdf") }), Set(ClassicCardArt.allAssetNames.map { $0 + ".pdf" }))
        XCTAssertEqual(files.filter { $0.hasSuffix(".png") }, [], "card faces ship as PDFs only")
        XCTAssertTrue(files.contains("manifest.json"))
        var total = 0
        for name in ClassicCardArt.allAssetNames {
            let data = try pdfData(name)
            total += data.count
            XCTAssertEqual(Array(data.prefix(5)), Array("%PDF-".utf8), "\(name) is not a PDF")
            // Image XObjects are streams, which PDF never packs into object streams, so their
            // dictionaries are always readable here: none may exist (the faces are paths only).
            XCTAssertNil(data.range(of: Data("/Image".utf8)), "\(name) embeds a raster image")
            XCTAssertLessThan(data.count, 80_000, "\(name) should stay small")
        }
        XCTAssertLessThan(total, 900_000, "all 52 faces together")
    }

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: cardsDirectory.appendingPathComponent("manifest.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The PDF page keeps the source SVG's 2:3 size, read from the build manifest.
    func testPagesKeepTheSourceSVGAspect() throws {
        let m = try manifest()
        XCTAssertEqual(m["format"] as? String, "pdf")
        let sourceW = try XCTUnwrap(m["sourceWidth"] as? Double ?? (m["sourceWidth"] as? Int).map(Double.init))
        let sourceH = try XCTUnwrap(m["sourceHeight"] as? Double ?? (m["sourceHeight"] as? Int).map(Double.init))
        XCTAssertEqual(sourceW, ClassicCardArt.pageWidth)
        XCTAssertEqual(sourceH, ClassicCardArt.pageHeight)
        XCTAssertEqual(sourceW / sourceH, ClassicCardArt.artAspect, accuracy: 1e-9)
    }

    /// The source deck draws every pip into a 2:3 box (too tall); the build reshapes them to usual
    /// playing-card proportions, and every card had its pips reshaped.
    func testPipsAreReshapedToNormalProportions() throws {
        let m = try manifest()
        let scales = try XCTUnwrap(m["pipScale"] as? [String: [String: Double]])
        let usual: [String: ClosedRange<Double>] = [
            "hearts": 0.9...1.05, "spades": 0.8...0.95, "clubs": 0.85...1.0, "diamonds": 0.72...0.85,
        ]
        for (suit, range) in usual {
            let s = try XCTUnwrap(scales[suit], suit)
            let aspect = (60 * (s["x"] ?? 0)) / (90 * (s["y"] ?? 0))
            XCTAssertTrue(range.contains(aspect), "\(suit) pip aspect \(aspect)")
        }
        let counts = try XCTUnwrap(m["reshapedPips"] as? [String: Int])
        for name in ClassicCardArt.allAssetNames {
            XCTAssertGreaterThanOrEqual(counts[name] ?? 0, 3, name) // at least the two index pips + one more
        }
        XCTAssertGreaterThanOrEqual(counts["hearts_10"] ?? 0, 12) // 10 pips + 2 index pips
    }

    /// CREDITS.md lists a source and a CC0 / public-domain licence for every face.
    func testCreditsCoverEveryImageWithACleanLicence() throws {
        let credits = try String(contentsOf: cardsDirectory.appendingPathComponent("CREDITS.md"), encoding: .utf8)
        let rows = credits.split(separator: "\n").filter { $0.hasPrefix("| `") }
        for name in ClassicCardArt.allAssetNames {
            let mine = rows.filter { $0.hasPrefix("| `\(name).pdf` |") }
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
        XCTAssertEqual(
            candidates.first,
            "/Applications/Spider Solitaire.app/Contents/Resources/SpiderSolitaire_SpiderSolitaire.bundle")
        XCTAssertTrue(candidates.contains("/Applications/Spider Solitaire.app/SpiderSolitaire_SpiderSolitaire.bundle"))
        XCTAssertTrue(
            candidates.contains(
                "/Applications/Spider Solitaire.app/Contents/MacOS/SpiderSolitaire_SpiderSolitaire.bundle"))
        XCTAssertEqual(Set(candidates).count, candidates.count)
    }

    func testBundleCandidatesForSwiftRun() {
        // `swift run`: no .app, Bundle.main is the build folder, the bundle sits next to the binary.
        let candidates = ClassicCardArt.bundleCandidates(
            resourcePath: nil,
            mainBundlePath: "/repo/.build/arm64-apple-macosx/debug",
            executablePath: "/repo/.build/arm64-apple-macosx/debug/SpiderSolitaire")
        XCTAssertEqual(
            candidates,
            [
                "/repo/.build/arm64-apple-macosx/debug/SpiderSolitaire_SpiderSolitaire.bundle",
                "/repo/.build/arm64-apple-macosx/debug/SpiderSolitaire_SpiderSolitaire.resources",
            ])
    }

    func testImagePathCandidatesCoverBothBundleLayouts() {
        XCTAssertEqual(
            ClassicCardArt.imagePathCandidates(bundlePath: "/b/R.bundle/", assetName: "hearts_king"),
            [
                "/b/R.bundle/Contents/Resources/Cards/hearts_king.pdf",
                "/b/R.bundle/Cards/hearts_king.pdf",
            ])
        XCTAssertEqual(ClassicCardArt.parentDirectory(of: "/a/b/c"), "/a/b")
        XCTAssertEqual(ClassicCardArt.parentDirectory(of: "/c"), "/")
        XCTAssertEqual(ClassicCardArt.parentDirectory(of: "c"), ".")
    }
}
