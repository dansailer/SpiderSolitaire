#if canImport(AppKit)
import AppKit
import CryptoKit
import Foundation
import Security
import SpiderUpdates

/// The macOS half of in-app updating: checksum, unzip, signature check and the bundle swap.
/// Decisions (requirement string, version rule, install plan, the helper script) live in
/// SpiderUpdates so they are tested on Linux too.
enum UpdateInstaller {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// A downloaded, checked update waiting for "Restart to Update".
    struct Prepared {
        let version: String
        /// Temporary folder on the app's volume holding the zip, the new app and later the backup.
        let workFolder: URL
        let newApp: URL
        let target: URL
    }

    /// The folder updates are staged in: on the same volume as the app, so the swap is two renames.
    static func makeWorkFolder(near app: URL) throws -> URL {
        // A fresh, unique folder each call (removed by the helper, or when discarded).
        try FileManager.default.url(
            for: FileManager.SearchPathDirectory.itemReplacementDirectory,
            in: FileManager.SearchPathDomainMask.userDomainMask, appropriateFor: app, create: true)
    }

    static func installPlan(for app: URL) -> InstallPlan {
        let parent: String = app.deletingLastPathComponent().path
        return InstallPlan.decide(
            appPath: app.path, parentWritable: FileManager.default.isWritableFile(atPath: parent))
    }

    /// SHA-256 of a file, read in 1 MB chunks.
    static func sha256(of file: URL) throws -> String {
        let handle: FileHandle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher: SHA256 = SHA256()
        while let chunk: Data = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return UpdateChecksum.hex(hasher.finalize())
    }

    static func verifyChecksum(zip: URL, checksumFile: URL) throws {
        let text: String = (try? String(contentsOf: checksumFile, encoding: .utf8)) ?? ""
        guard let expected: String = UpdateChecksum.parse(text) else {
            throw Failure(description: "The release's checksum file could not be read.")
        }
        guard UpdateChecksum.matches(try sha256(of: zip), expected) else {
            throw Failure(description: "The download is damaged (its checksum does not match).")
        }
    }

    /// `ditto -x -k`, the counterpart of how package.sh zips the app (keeps signatures intact).
    static func unzip(_ zip: URL, into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, folder.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "The download could not be unpacked.") }
        let apps: [URL] = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { (url: URL) -> Bool in url.pathExtension == "app" }
        guard apps.count == 1 else { throw Failure(description: "The download does not contain the app.") }
        return apps[0]
    }

    /// The new app must be validly signed by our Developer ID team with our bundle identifier,
    /// and newer than the running version.
    static func verify(app: URL, bundleIdentifier: String, currentVersion: String?) throws {
        try verifySignature(app: app, bundleIdentifier: bundleIdentifier)
        guard let info: NSDictionary = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
            info["CFBundleIdentifier"] as? String == bundleIdentifier
        else { throw Failure(description: "The downloaded app is not Spider Solitaire.") }
        guard UpdateTrust.isNewer(candidate: info["CFBundleShortVersionString"] as? String, than: currentVersion)
        else { throw Failure(description: "The downloaded app is not newer than this one.") }
    }

    static func verifySignature(app: URL, bundleIdentifier: String) throws {
        try checkSignature(
            app, requirement: UpdateTrust.requirement(bundleIdentifier: bundleIdentifier),
            failure: "The downloaded app is not signed by Spider Solitaire's developer")
    }

    /// A copy of this app (Move to Applications) is complete: its signature is valid for our
    /// identifier (any signer, so development builds pass too) and its Info.plist says it is us.
    static func verifyIntact(app: URL, bundleIdentifier: String) throws {
        try checkSignature(
            app, requirement: "identifier \"\(bundleIdentifier)\"", failure: "The copy is incomplete or damaged")
        let info: NSDictionary? = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleIdentifier else {
            throw Failure(description: "The copy is not Spider Solitaire.")
        }
    }

    private static func checkSignature(_ app: URL, requirement text: String, failure: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else {
            throw Failure(description: "\(app.lastPathComponent) could not be checked.")
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
            let requirement
        else { throw Failure(description: "The signature requirement is invalid.") }
        let flags: SecCSFlags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status: OSStatus = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            let reason: String = (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
            throw Failure(description: "\(failure) (\(reason)).")
        }
    }

    /// Writes the helper script, starts it (it waits for this process to exit), and returns.
    /// The caller then quits the app.
    static func launchHelper(for update: Prepared, relaunch: String = "/usr/bin/open") throws {
        let script: URL = update.workFolder.appendingPathComponent("install.sh")
        try InstallScript.text.write(to: script, atomically: true, encoding: .utf8)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments =
            [script.path]
            + InstallScript.arguments(
                pid: ProcessInfo.processInfo.processIdentifier, target: update.target.path,
                newApp: update.newApp.path,
                backup: update.workFolder.appendingPathComponent("previous.app").path,
                workFolder: update.workFolder.path, relaunch: relaunch)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
#endif
