import Foundation
import XCTest
@testable import SpiderUpdates

final class SemanticVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion(1, 2, 0))
        XCTAssertEqual(SemanticVersion("2"), SemanticVersion(2, 0, 0))
        XCTAssertEqual(SemanticVersion("1.0.0-beta.2+exp.sha"), SemanticVersion(1, 0, 0, prerelease: ["beta", "2"]))
        XCTAssertEqual(SemanticVersion(" 1.0.0\n"), SemanticVersion(1, 0, 0))
        for bad in ["", "v", "1.2.3.4", "1..2", "a.b.c", "1.2.x", "1.0.0-", "1.0.0-a..b", "-1.0.0", "١.٢.٣"] {
            XCTAssertNil(SemanticVersion(bad), bad)
        }
    }

    func testOrderingFollowsSemver() {
        // semver.org §11 example chain.
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                     "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "1.10.0", "2.0.0"].map { SemanticVersion($0)! }
        for (a, b) in zip(chain, chain.dropFirst()) {
            XCTAssertLessThan(a, b, "\(a) < \(b)")
            XCTAssertFalse(b < a)
        }
        XCTAssertEqual(SemanticVersion("1.2.3+build.1"), SemanticVersion("1.2.3+build.2"))
        XCTAssertEqual(SemanticVersion(1, 2, 3, prerelease: ["rc", "1"]).description, "1.2.3-rc.1")
    }
}

final class ReleaseTests: XCTestCase {
    let json = """
    {
      "url": "https://api.github.com/repos/dansailer/SpiderSolitaire/releases/1",
      "html_url": "https://github.com/dansailer/SpiderSolitaire/releases/tag/v1.2.0",
      "tag_name": "v1.2.0",
      "name": "v1.2.0",
      "draft": false,
      "prerelease": false,
      "body": "## What's Changed\\r\\n* Check for updates by @dansailer in [#3](https://github.com/x/y/pull/3)\\r\\n\\r\\n**Full Changelog**: https://github.com/x/y/compare/v1.1.0...v1.2.0",
      "assets": [
        {"name": "SpiderSolitaire.zip.sha256", "size": 90, "browser_download_url": "https://github.com/dansailer/SpiderSolitaire/releases/download/v1.2.0/SpiderSolitaire.zip.sha256"},
        {"name": "SpiderSolitaire.zip", "size": 2400000, "browser_download_url": "https://github.com/dansailer/SpiderSolitaire/releases/download/v1.2.0/SpiderSolitaire.zip"}
      ]
    }
    """

    func release() throws -> ReleaseInfo { try ReleaseInfo.decode(Data(json.utf8)) }

    func testDecodesGitHubJSON() throws {
        let r = try release()
        XCTAssertEqual(r.version, SemanticVersion(1, 2, 0))
        XCTAssertEqual(r.appAsset?.browserDownloadURL.lastPathComponent, "SpiderSolitaire.zip")
        XCTAssertEqual(r.htmlURL.absoluteString, "https://github.com/dansailer/SpiderSolitaire/releases/tag/v1.2.0")
    }

    func testStatus() throws {
        let r = try release()
        XCTAssertEqual(UpdateStatus.evaluate(currentVersion: "1.1.9", release: r),
                       .available(current: SemanticVersion(1, 1, 9), latest: SemanticVersion(1, 2, 0), release: r))
        XCTAssertEqual(UpdateStatus.evaluate(currentVersion: "1.2.0", release: r), .upToDate(current: SemanticVersion(1, 2, 0)))
        XCTAssertEqual(UpdateStatus.evaluate(currentVersion: "1.3.0", release: r), .upToDate(current: SemanticVersion(1, 3, 0)))
        XCTAssertEqual(UpdateStatus.evaluate(currentVersion: "1.2.0-rc.1", release: r)?.isUpdate, true)
        XCTAssertEqual(UpdateStatus.evaluate(currentVersion: nil, release: r), .unknownCurrent(latest: SemanticVersion(1, 2, 0), release: r))
        XCTAssertFalse(UpdateStatus.evaluate(currentVersion: "1.2.0", release: r)!.isUpdate)
    }

    func testIgnoresDraftsPrereleasesAndOddTags() throws {
        let pre = json.replacingOccurrences(of: "\"prerelease\": false", with: "\"prerelease\": true")
        XCTAssertNil(UpdateStatus.evaluate(currentVersion: "1.0.0", release: try ReleaseInfo.decode(Data(pre.utf8))))
        let odd = json.replacingOccurrences(of: "\"tag_name\": \"v1.2.0\"", with: "\"tag_name\": \"latest\"")
        XCTAssertNil(UpdateStatus.evaluate(currentVersion: "1.0.0", release: try ReleaseInfo.decode(Data(odd.utf8))))
    }

    func testExcerpt() throws {
        XCTAssertEqual(ReleaseNotes.excerpt(try release().body),
                       "What's Changed\n• Check for updates by @dansailer in #3\n\nFull Changelog: https://github.com/x/y/compare/v1.1.0...v1.2.0")
        let long = String(repeating: "word ", count: 300)
        let cut = ReleaseNotes.excerpt(long, limit: 100)
        XCTAssertLessThanOrEqual(cut.count, 101)
        XCTAssertTrue(cut.hasSuffix("word…"))
        XCTAssertEqual(ReleaseNotes.excerpt(nil), "")
        XCTAssertEqual(ReleaseNotes.excerpt("<!-- hidden -->\n\n\nText"), "Text")
    }
}

final class PolicyTests: XCTestCase {
    func testOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UpdateCheckPolicy.shouldCheckAutomatically(enabled: true, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheckPolicy.shouldCheckAutomatically(enabled: false, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheckPolicy.shouldCheckAutomatically(enabled: true, lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheckAutomatically(enabled: true, lastCheck: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheckAutomatically(enabled: true, lastCheck: now.addingTimeInterval(86_400 * 30), now: now))
    }

    func testRequest() {
        let h = UpdateRequest.headers(appVersion: "1.2.0")
        XCTAssertTrue(h["User-Agent"]!.hasPrefix("SpiderSolitaire/1.2.0"))
        XCTAssertEqual(h["Accept"], "application/vnd.github+json")
        XCTAssertNil(h["Authorization"])
        XCTAssertEqual(ProjectLinks.latestReleaseAPI.absoluteString,
                       "https://api.github.com/repos/dansailer/SpiderSolitaire/releases/latest")
        XCTAssertFalse(UpdateRequest.failureMessage(statusCode: nil).contains("!"))
        XCTAssertNotEqual(UpdateRequest.failureMessage(statusCode: 404), UpdateRequest.failureMessage(statusCode: 500))
    }
}
