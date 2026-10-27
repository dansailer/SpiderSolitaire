import Foundation
import XCTest

/// Guards the M8 packaging inputs (Packaging/Info.plist, scripts/package.sh) without needing macOS.
final class PackagingTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SpiderPersistenceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    private func substitutedPlist() throws -> [String: Any] {
        let url: URL = repoRoot.appendingPathComponent("Packaging/Info.plist")
        let template: String = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(template.contains("__VERSION__"))
        XCTAssertTrue(template.contains("__BUILD__"))
        let text: String = template
            .replacingOccurrences(of: "__VERSION__", with: "1.0.0")
            .replacingOccurrences(of: "__BUILD__", with: "42")
        let object: Any = try PropertyListSerialization.propertyList(from: Data(text.utf8), options: [], format: nil)
        guard let dictionary: [String: Any] = object as? [String: Any] else {
            XCTFail("Info.plist is not a dictionary")
            return [:]
        }
        return dictionary
    }

    func testInfoPlistHasRequiredKeys() throws {
        let plist: [String: Any] = try substitutedPlist()
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.dansailer.SpiderSolitaire")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Spider Solitaire")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Spider Solitaire")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "SpiderSolitaire")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "42")
        let category: String = try XCTUnwrap(plist["LSApplicationCategoryType"] as? String)
        XCTAssertTrue(category.hasPrefix("public.app-category.") && category.contains("games"), category)
    }

    func testExecutableNameMatchesPackageProduct() throws {
        let manifest: String = try String(contentsOf: repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("name: \"SpiderSolitaire\""))
        XCTAssertTrue(manifest.contains("name: \"SpiderIcon\""))
    }

    func testPackageScriptIsStrictBashAndExecutable() throws {
        let url: URL = repoRoot.appendingPathComponent("scripts/package.sh")
        let script: String = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("swift build -c release"))
        XCTAssertTrue(script.contains("codesign --force --deep -s -"))
        XCTAssertTrue(script.contains("build/SpiderSolitaire.zip") || script.contains("SpiderSolitaire.zip"))
        XCTAssertTrue(script.contains("Spider Solitaire.app") || script.contains("$APP_NAME.app"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path), "package.sh must be chmod +x")
        let lastLine: String = script.split(separator: "\n").last.map(String.init) ?? ""
        XCTAssertEqual(lastLine, "echo \"$APP\"", "the .app path must be the last thing printed")
    }
}
