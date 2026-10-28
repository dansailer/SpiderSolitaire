#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import SpiderCore
import XCTest

@testable import SpiderBoard

/// macOS only: the shipped PDFs open, are vector and render at exactly the requested pixel size.
final class ClassicCardRendererTests: XCTestCase {
    private func document(_ name: String) throws -> CGPDFDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SpiderSolitaire/Resources/Cards/\(name).pdf")
        return try XCTUnwrap(CGPDFDocument(url as CFURL), name)
    }

    func testEveryPDFIsOneVectorPageOfTheSourceSize() throws {
        for name in ClassicCardArt.allAssetNames {
            let doc = try document(name)
            XCTAssertEqual(doc.numberOfPages, 1, name)
            let page = try XCTUnwrap(doc.page(at: 1), name)
            let box = page.getBoxRect(CGPDFBox.mediaBox)
            XCTAssertEqual(Double(box.width), ClassicCardArt.pageWidth, accuracy: 0.01, name)
            XCTAssertEqual(Double(box.height), ClassicCardArt.pageHeight, accuracy: 0.01, name)
            XCTAssertEqual(imageXObjects(page), 0, "\(name) embeds a raster image")
        }
    }

    func testRenderMatchesThePixelSizeAndCentresTheArt() throws {
        let pixels = PixelSize(width: 240, height: 324)
        let image = try XCTUnwrap(ClassicCardRenderer.render(try document("spades_king"), pixels: pixels))
        XCTAssertEqual(image.width, 240)
        XCTAssertEqual(image.height, 324)
        let alpha = try alphaColumns(image)
        // Art is 216 px wide, centred: 12 transparent columns each side, ink in the middle.
        XCTAssertEqual(alpha[0], 0)
        XCTAssertEqual(alpha[10], 0)
        XCTAssertEqual(alpha[229], 0)
        XCTAssertEqual(alpha[239], 0)
        XCTAssertGreaterThan(alpha[120], 0)
    }

    /// Largest alpha per column.
    private func alphaColumns(_ image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ok: Bool = data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard
                let ctx = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(ok)
        var columns = [UInt8](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w { columns[x] = max(columns[x], data[(y * w + x) * 4 + 3]) }
        }
        return columns
    }

    /// Image XObjects in the page's resources, including inside form XObjects.
    private func imageXObjects(_ page: CGPDFPage) -> Int {
        guard let dictionary = page.dictionary else { return 0 }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return 0 }
        return imageXObjects(inResources: resources, depth: 0)
    }

    private func imageXObjects(inResources resources: CGPDFDictionaryRef, depth: Int) -> Int {
        var xobjects: CGPDFDictionaryRef?
        guard depth < 8, CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return 0 }
        var streams: [CGPDFDictionaryRef] = []
        CGPDFDictionaryApplyBlock(
            xobjects,
            { (_: UnsafePointer<CChar>, object: CGPDFObjectRef, _: UnsafeMutableRawPointer?) -> Bool in
                var stream: CGPDFStreamRef?
                if CGPDFObjectGetValue(object, CGPDFObjectType.stream, &stream), let stream,
                    let dict = CGPDFStreamGetDictionary(stream)
                {
                    streams.append(dict)
                }
                return true
            }, nil)
        var count = 0
        for dict in streams {
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" {
                count += 1
            }
            var inner: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dict, "Resources", &inner), let inner {
                count += imageXObjects(inResources: inner, depth: depth + 1)
            }
        }
        return count
    }
}
#endif
