import Foundation
import XCTest

@testable import SpiderUpdates

final class UpdateChecksumTests: XCTestCase {
    private let digest: String = String(repeating: "ab", count: 32)

    func testParsesShasumOutput() {
        XCTAssertEqual(UpdateChecksum.parse("\(digest)  SpiderSolitaire.zip\n"), digest)
        XCTAssertEqual(UpdateChecksum.parse("\(digest.uppercased()) *SpiderSolitaire.zip"), digest)
        XCTAssertEqual(UpdateChecksum.parse("\(digest)  build/SpiderSolitaire.zip"), digest)
        XCTAssertEqual(UpdateChecksum.parse("\n\(digest)\n"), digest)
        let other: String = String(repeating: "cd", count: 32)
        XCTAssertEqual(UpdateChecksum.parse("\(other)  Other.zip\n\(digest)  SpiderSolitaire.zip"), digest)
    }

    func testRejectsAnythingElse() {
        XCTAssertNil(UpdateChecksum.parse(""))
        XCTAssertNil(UpdateChecksum.parse("\(digest)  Other.zip"))
        XCTAssertNil(UpdateChecksum.parse(String(digest.dropLast())))
        XCTAssertNil(UpdateChecksum.parse(String(repeating: "g", count: 64)))
        XCTAssertNil(UpdateChecksum.parse("<html>Not Found</html>"))
    }

    func testHexAndMatching() {
        XCTAssertEqual(UpdateChecksum.hex([0x00, 0x0f, 0xa0, 0xff]), "000fa0ff")
        XCTAssertTrue(UpdateChecksum.matches(digest, digest.uppercased()))
        XCTAssertFalse(UpdateChecksum.matches(digest, String(repeating: "ab", count: 31) + "ac"))
        XCTAssertFalse(UpdateChecksum.matches("", ""))
        XCTAssertFalse(UpdateChecksum.matches("abc", "abc"))
    }
}

final class UpdateTrustTests: XCTestCase {
    func testRequirementPinsTeamDeveloperIDAndIdentifier() {
        let text: String = UpdateTrust.requirement()
        XCTAssertTrue(text.hasPrefix("anchor apple generic"))
        XCTAssertTrue(text.contains("identifier \"com.dansailer.SpiderSolitaire\""))
        XCTAssertTrue(text.contains("certificate leaf[subject.OU] = \"595TEE9LSF\""))
        // Developer ID: the intermediate (6.2.6) and leaf (6.1.13) markers, so an Apple Development
        // or Mac App Store certificate of the same team does not pass.
        XCTAssertTrue(text.contains("certificate 1[field.1.2.840.113635.100.6.2.6] exists"))
        XCTAssertTrue(text.contains("certificate leaf[field.1.2.840.113635.100.6.1.13] exists"))
        XCTAssertTrue(UpdateTrust.requirement(bundleIdentifier: "a.b", teamIdentifier: "T").contains("\"T\""))
    }

    func testOnlyStrictlyNewerVersionsInstall() {
        XCTAssertTrue(UpdateTrust.isNewer(candidate: "1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateTrust.isNewer(candidate: "1.1.0", than: "1.0.9"))
        XCTAssertTrue(UpdateTrust.isNewer(candidate: "1.0.0", than: "1.0.0-rc.1"))
        XCTAssertFalse(UpdateTrust.isNewer(candidate: "1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateTrust.isNewer(candidate: "0.9.0", than: "1.0.0"))
        XCTAssertFalse(UpdateTrust.isNewer(candidate: nil, than: "1.0.0"))
        XCTAssertFalse(UpdateTrust.isNewer(candidate: "1.0.1", than: nil))
        XCTAssertFalse(UpdateTrust.isNewer(candidate: "banana", than: "1.0.0"))
    }

    func testTrustedAssetURLs() {
        let good: String = "https://github.com/dansailer/SpiderSolitaire/releases/download/v1.0.1/SpiderSolitaire.zip"
        XCTAssertTrue(UpdateTrust.isTrustedAssetURL(URL(string: good)!))
        for bad in [
            "http://github.com/dansailer/SpiderSolitaire/releases/download/v1.0.1/SpiderSolitaire.zip",
            "https://github.com/someone/SpiderSolitaire/releases/download/v1/SpiderSolitaire.zip",
            "https://github.com/dansailer/SpiderSolitaire/releases/download/../../x/SpiderSolitaire.zip",
            "https://github.com.evil.example/dansailer/SpiderSolitaire/releases/download/v1/SpiderSolitaire.zip",
            "file:///tmp/SpiderSolitaire.zip",
        ] {
            XCTAssertFalse(UpdateTrust.isTrustedAssetURL(URL(string: bad)!), bad)
        }
    }

    func testReleaseChecksumAsset() throws {
        let json: String = """
            {"tag_name": "v1.0.1", "html_url": "https://github.com/dansailer/SpiderSolitaire/releases/tag/v1.0.1",
             "assets": [
               {"name": "SpiderSolitaire.zip", "size": 10,
                "browser_download_url": "https://github.com/dansailer/SpiderSolitaire/releases/download/v1.0.1/SpiderSolitaire.zip"},
               {"name": "SpiderSolitaire.zip.sha256", "size": 85,
                "browser_download_url": "https://github.com/dansailer/SpiderSolitaire/releases/download/v1.0.1/SpiderSolitaire.zip.sha256"}
             ]}
            """
        let release: ReleaseInfo = try ReleaseInfo.decode(Data(json.utf8))
        XCTAssertEqual(release.appAsset?.name, "SpiderSolitaire.zip")
        XCTAssertEqual(release.checksumAsset?.size, 85)
    }
}

final class AppLocationTests: XCTestCase {
    private let home: String = "/Users/me"

    func testLocations() {
        XCTAssertTrue(
            AppLocation.isTranslocated("/private/var/folders/x/T/AppTranslocation/1234/d/Spider Solitaire.app"))
        XCTAssertFalse(AppLocation.isTranslocated("/Applications/Spider Solitaire.app"))
        XCTAssertTrue(AppLocation.isInDownloads("/Users/me/Downloads/Spider Solitaire.app", home: home))
        XCTAssertTrue(AppLocation.isInDownloads("/Users/me/Downloads/x/Spider Solitaire.app", home: home + "/"))
        XCTAssertFalse(AppLocation.isInDownloads("/Users/me/DownloadsOld/Spider Solitaire.app", home: home))
        XCTAssertTrue(AppLocation.isInApplications("/Applications/Spider Solitaire.app", home: home))
        XCTAssertTrue(AppLocation.isInApplications("/Users/me/Applications/Spider Solitaire.app", home: home))
        XCTAssertFalse(AppLocation.isInApplications("/Users/me/Desktop/Spider Solitaire.app", home: home))
    }

    func testMoveOffer() {
        let downloads: String = "/Users/me/Downloads/Spider Solitaire.app"
        XCTAssertTrue(
            AppLocation.shouldOfferMove(
                appPath: downloads, home: home, suppressed: false, applicationsCopyExists: false))
        XCTAssertFalse(
            AppLocation.shouldOfferMove(appPath: downloads, home: home, suppressed: true, applicationsCopyExists: false)
        )
        XCTAssertFalse(
            AppLocation.shouldOfferMove(appPath: downloads, home: home, suppressed: false, applicationsCopyExists: true)
        )
        XCTAssertTrue(
            AppLocation.shouldOfferMove(
                appPath: "/private/var/folders/a/AppTranslocation/U/d/Spider Solitaire.app", home: home,
                suppressed: false, applicationsCopyExists: false))
        for path in ["/Applications/Spider Solitaire.app", "/Users/me/Desktop/Spider Solitaire.app", "/x/.build/debug"]
        {
            XCTAssertFalse(
                AppLocation.shouldOfferMove(
                    appPath: path, home: home, suppressed: false, applicationsCopyExists: false),
                path)
        }
    }

    func testInstallPlan() {
        XCTAssertEqual(
            InstallPlan.decide(appPath: "/Applications/Spider Solitaire.app", parentWritable: true),
            .inPlace(target: "/Applications/Spider Solitaire.app"))
        XCTAssertEqual(
            InstallPlan.decide(appPath: "/Applications/Spider Solitaire.app", parentWritable: false),
            .manual(reason: InstallPlan.notWritableMessage))
        XCTAssertEqual(
            InstallPlan.decide(
                appPath: "/private/var/folders/a/AppTranslocation/U/d/Spider Solitaire.app", parentWritable: true),
            .manual(reason: InstallPlan.translocatedMessage))
        XCTAssertEqual(
            InstallPlan.decide(appPath: "/repo/.build/debug", parentWritable: true),
            .manual(reason: InstallPlan.notAnAppMessage))
    }
}

/// Runs the real helper script with /bin/sh on throwaway folders (Linux and macOS).
final class InstallScriptTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Layout {
        let target: URL
        let new: URL
        let backup: URL
        let work: URL
        let marker: URL
    }

    private func makeLayout(withNewApp: Bool = true) throws -> Layout {
        let manager: FileManager = FileManager.default
        let target: URL = root.appendingPathComponent("Apps/Spider Solitaire.app")
        let work: URL = root.appendingPathComponent("work")
        let new: URL = work.appendingPathComponent("new/Spider Solitaire.app")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try "old".write(to: target.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try manager.createDirectory(at: work.appendingPathComponent("new"), withIntermediateDirectories: true)
        if withNewApp {
            try manager.createDirectory(at: new, withIntermediateDirectories: true)
            try "new".write(to: new.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        }
        return Layout(
            target: target, new: new, backup: work.appendingPathComponent("previous.app"), work: work,
            marker: root.appendingPathComponent("relaunched"))
    }

    /// A relaunch command that records what it was asked to open.
    private func relaunchRecorder(_ marker: URL) throws -> String {
        let script: URL = root.appendingPathComponent("relaunch.sh")
        try "#!/bin/sh\necho \"$1\" >> \"\(marker.path)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    private func run(_ layout: Layout, pid: Int32, path: String? = nil) throws -> Int32 {
        let script: URL = root.appendingPathComponent("install.sh")
        try InstallScript.text.write(to: script, atomically: true, encoding: .utf8)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments =
            [script.path]
            + InstallScript.arguments(
                pid: pid, target: layout.target.path, newApp: layout.new.path, backup: layout.backup.path,
                workFolder: layout.work.path, relaunch: try relaunchRecorder(layout.marker))
        if let path {
            var environment: [String: String] = ProcessInfo.processInfo.environment
            environment["PATH"] = path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
            process.environment = environment
        }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func content(_ app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("version"), encoding: .utf8)
    }

    private func relaunched(_ layout: Layout) -> [String] {
        ((try? String(contentsOf: layout.marker, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    /// A process id that is no longer running.
    private func exitedPID() throws -> Int32 {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 0"]
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    func testSwapsBundleRelaunchesAndCleansUp() throws {
        let layout: Layout = try makeLayout()
        XCTAssertEqual(try run(layout, pid: try exitedPID()), 0)
        XCTAssertEqual(content(layout.target), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.work.path), "work folder and backup removed")
        XCTAssertEqual(relaunched(layout), [layout.target.path])
    }

    func testWaitsForTheAppToQuit() throws {
        let layout: Layout = try makeLayout()
        let app: Process = Process()
        app.executableURL = URL(fileURLWithPath: "/bin/sh")
        app.arguments = ["-c", "sleep 0.6"]
        try app.run()
        let start: Date = Date()
        XCTAssertEqual(try run(layout, pid: app.processIdentifier), 0)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.4, "did not wait for the app")
        app.waitUntilExit()
        XCTAssertEqual(content(layout.target), "new")
    }

    func testMissingNewAppLeavesTheOldOneAndRelaunchesIt() throws {
        let layout: Layout = try makeLayout(withNewApp: false)
        XCTAssertEqual(try run(layout, pid: try exitedPID()), 1)
        XCTAssertEqual(content(layout.target), "old")
        XCTAssertEqual(relaunched(layout), [layout.target.path])
        let log: String =
            (try? String(contentsOf: layout.work.appendingPathComponent("install.log"), encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("new app missing"), log)
    }

    func testRollsBackWhenTheNewAppCannotBeMovedIn() throws {
        let layout: Layout = try makeLayout()
        // A `mv` that refuses to move the new app (even as root, where permissions don't help).
        let bin: URL = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let realMove: String = FileManager.default.fileExists(atPath: "/bin/mv") ? "/bin/mv" : "/usr/bin/mv"
        let fake: String = "#!/bin/sh\ncase \"$1\" in \"\(layout.new.path)\") exit 1 ;; esac\nexec \(realMove) \"$@\"\n"
        try fake.write(to: bin.appendingPathComponent("mv"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent("mv").path)
        XCTAssertEqual(try run(layout, pid: try exitedPID(), path: bin.path), 1)
        XCTAssertEqual(content(layout.target), "old", "old app restored")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.backup.path))
        XCTAssertEqual(relaunched(layout), [layout.target.path])
    }

    func testArgumentsArePositional() {
        XCTAssertEqual(
            InstallScript.arguments(
                pid: 42, target: "/A/X.app", newApp: "/w/n/X.app", backup: "/w/b.app", workFolder: "/w"),
            ["42", "/A/X.app", "/w/n/X.app", "/w/b.app", "/w", "/usr/bin/open"])
        XCTAssertFalse(InstallScript.text.contains("\\("), "no interpolation into the script")
    }
}
