import XCTest
import SpiderCore
@testable import SpiderBoard

final class VectorArtTests: XCTestCase {
    private func inside(_ inner: BoardRect, _ outer: BoardRect, tolerance: Double = 1e-6) -> Bool {
        inner.minX >= outer.minX - tolerance && inner.minY >= outer.minY - tolerance
            && inner.maxX <= outer.maxX + tolerance && inner.maxY <= outer.maxY + tolerance
    }

    /// The spade is never stretched: same proportions in a wide, a tall and a square box.
    func testSpadeKeepsItsAspectInAnyBox() {
        let boxes = [BoardRect(x: 0, y: 0, width: 300, height: 100), BoardRect(x: 10, y: 20, width: 50, height: 400),
                     BoardRect(x: -5, y: 5, width: 80, height: 80)]
        for box in boxes {
            let b = SpadePip.path(in: box).bounds
            XCTAssertEqual(b.width / b.height, SpadePip.aspect, accuracy: 1e-9, "\(box)")
            XCTAssertTrue(inside(b, box), "\(box)")
            XCTAssertEqual(b.midX, box.midX, accuracy: 1e-9)
            XCTAssertEqual(b.midY, box.midY, accuracy: 1e-9)
            XCTAssertTrue(abs(b.width - box.width) < 1e-9 || abs(b.height - box.height) < 1e-9, "fills one dimension")
        }
    }

    func testSpadeIsMirrorSymmetric() {
        let path = SpadePip.path(in: BoardRect(x: 0, y: 0, width: 86, height: 100))
        var xs: [Double] = []
        for command in path.commands {
            switch command {
            case .move(let p), .line(let p): xs.append(p.x)
            case .curve(let a, let b, let p): xs += [a.x, b.x, p.x]
            case .close: break
            }
        }
        XCTAssertEqual(xs.reduce(0, +) / Double(xs.count), 43, accuracy: 1e-6)
    }

    func testAffineComposesInOrderAndRotationKeepsLengths() {
        let t = Affine2D.translation(10, 0).then(.rotation(degrees: 90))
        let p = t.apply(BoardPoint(x: 0, y: 0))
        XCTAssertEqual(p.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p.y, 10, accuracy: 1e-9) // clockwise on screen: +x turns into +y
        XCTAssertEqual(Affine2D.rotation(degrees: 37).lengthScale, 1, accuracy: 1e-9)
        XCTAssertEqual(Affine2D.scale(3).then(.rotation(degrees: -13)).lengthScale, 3, accuracy: 1e-9)
    }

    func testCardBackStaysInsideTheCardAtEverySize() {
        for width in [BoardLayout.minCardWidth, 71, BoardLayout.maxCardWidth] {
            let size = BoardSize(width: width, height: width * BoardLayout.cardAspect)
            let card = BoardRect(x: 0, y: 0, width: size.width, height: size.height)
            let scene = CardBackArt.scene(size: size)
            XCTAssertEqual(scene.size, size)
            for item in scene.items where item.clip == nil {
                XCTAssertTrue(inside(item.path.bounds, card), "\(width): \(item.path.bounds)")
            }
            // The lattice runs past the field and must be clipped.
            XCTAssertTrue(scene.items.contains { $0.clip != nil })
        }
    }

    func testCardBackOrnamentIsACentredRosette() {
        let size = BoardSize(width: 100, height: 135)
        let rosette = Rosette.items(center: BoardPoint(x: 50, y: 67.5), radius: 20, lineWidth: 1.5)
        XCTAssertEqual(rosette.count, 1 + 8 + 2) // lozenge, eight petals, two centre discs
        let lozenge = rosette[0].path.bounds
        XCTAssertEqual(lozenge.midX, size.width / 2, accuracy: 1e-9)
        XCTAssertEqual(lozenge.midY, size.height / 2, accuracy: 1e-9)
        let back = CardBackArt.scene(size: size)
        XCTAssertTrue(back.items.contains(rosette[0]))
    }

    func testAppIconArtStaysOnTheTile() {
        let scene = AppIconArt.scene()
        XCTAssertEqual(scene.size, BoardSize(width: 1024, height: 1024))
        let canvas = BoardRect(x: 0, y: 0, width: 1024, height: 1024)
        let tile = BoardRect(x: 100, y: 100, width: 824, height: 824)
        for item in scene.items {
            // Clipped items (the lattice) only show inside their clip.
            let visible = item.clip?.bounds ?? item.path.bounds
            XCTAssertTrue(inside(visible, canvas))
            XCTAssertTrue(inside(visible, tile), "\(visible)")
        }
    }

    func testSVGHasOnePathPerItem() {
        let scene = CardBackArt.scene(size: BoardSize(width: 120, height: 162))
        let svg = scene.svg()
        XCTAssertTrue(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"162\""))
        let drawn = svg.split(separator: "\n").filter { $0.hasPrefix("<path ") }
        XCTAssertEqual(drawn.count, scene.items.count)
        XCTAssertTrue(svg.hasSuffix("</svg>\n"))
    }
}
