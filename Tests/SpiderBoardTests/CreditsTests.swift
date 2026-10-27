import Foundation
import XCTest

@testable import SpiderBoard

final class CreditsTests: XCTestCase {
    func testLinksAreHTTPSAndMatchCreditsFile() throws {
        let creditsFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SpiderSolitaire/Resources/Cards/CREDITS.md")
        let text = try String(contentsOf: creditsFile, encoding: .utf8)
        for credit in Credits.all {
            for link in credit.links {
                XCTAssertTrue(link.url.hasPrefix("https://"), link.url)
                if link.url.contains("commons.wikimedia.org") || link.url.contains("creativecommons.org") {
                    XCTAssertTrue(text.contains(link.url), "\(link.url) is not in CREDITS.md")
                }
            }
        }
    }

    func testNamesAndLicences() {
        let all = Credits.all.map { $0.title + " " + $0.detail }.joined(separator: " ")
        XCTAssertTrue(all.contains("Dmitry Fomin"))
        XCTAssertTrue(all.contains("CC0 1.0"))
        XCTAssertTrue(all.contains("Byron Knoll"))
        XCTAssertTrue(all.contains("public domain"))
        XCTAssertTrue(all.contains("MIT"))
        XCTAssertFalse(all.lowercased().replacingOccurrences(of: "spider solitaire", with: "").contains("spider"))
    }
}
