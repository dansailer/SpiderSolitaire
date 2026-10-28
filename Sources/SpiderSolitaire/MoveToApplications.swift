#if canImport(AppKit)
import AppKit
import Foundation
import SpiderUpdates

/// Once at launch: when the app runs from Downloads or translocated (where it can't update itself),
/// offer to move it to /Applications. Only when there is no copy there yet, so nothing is ever
/// replaced; "Don't ask again" stops the offer for good.
///
/// Move copies the app and checks the copy, then quits normally (the save prompt may still cancel).
/// Only once this process has exited does a helper (`MoveScript`) open the copy, so two instances
/// never share the store. The copy puts the original in the Trash once it is running; if the copy
/// won't open, the helper reopens the original, which says so and keeps running.
@MainActor
enum MoveToApplications {
    static let suppressKey: String = "SpiderSolitaireDontOfferMoveToApplications"

    private struct Pending {
        let copy: URL
        let original: URL
    }
    private static var pending: Pending?

    static var applications: URL {
        DebugMoveTesting.applications ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    static func offerIfNeeded() {
        let app: URL = Bundle.main.bundleURL
        let destination: URL = applications.appendingPathComponent(app.lastPathComponent)
        guard
            DebugMoveTesting.isActive
                || AppLocation.shouldOfferMove(
                    appPath: app.path, home: NSHomeDirectory(),
                    suppressed: UserDefaults.standard.bool(forKey: suppressKey),
                    applicationsCopyExists: FileManager.default.fileExists(atPath: destination.path))
        else { return }
        if !DebugMoveTesting.isActive {
            let alert: NSAlert = NSAlert()
            alert.messageText = "Move Spider Solitaire to your Applications folder?"
            alert.informativeText =
                "It's running from your Downloads folder. In Applications it can install updates itself, "
                + "and you'll find it in Launchpad and Spotlight."
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Not Now")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
            let response: NSApplication.ModalResponse = alert.runModal()
            if alert.suppressionButton?.state == NSControl.StateValue.on {
                UserDefaults.standard.set(true, forKey: suppressKey)
            }
            guard response == NSApplication.ModalResponse.alertFirstButtonReturn else { return }
        }
        do {
            try copyAndCheck(app, to: destination)
        } catch {
            show(
                "Spider Solitaire couldn't be moved",
                "Drag it to your Applications folder in Finder instead. (\(error))")
            return
        }
        pending = Pending(copy: destination, original: app)
        DebugMoveTesting.log("copied, quitting")
        NSApplication.shared.terminate(nil)
    }

    /// Copies (never overwrites), drops the quarantine flag on the copy, and checks that the copy is
    /// a complete, validly signed Spider Solitaire. A copy that fails the check goes to the Trash
    /// (it is the one just made; the original is never touched here).
    private static func copyAndCheck(_ app: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: app, to: destination)
        do {
            let xattr: Process = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try xattr.run()
            xattr.waitUntilExit()
            try UpdateInstaller.verifyIntact(app: destination, bundleIdentifier: ProjectLinks.bundleIdentifier)
        } catch {
            try? FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            throw error
        }
    }

    /// The quit was cancelled: stay as we are; the copy is ready in Applications.
    static func quitWasCancelled() {
        guard let pending else { return }
        self.pending = nil
        show(
            "Spider Solitaire is in your Applications folder",
            "You're still using this copy. Quit and open Spider Solitaire from Applications when you're ready.")
        DebugMoveTesting.log("quit cancelled, copy kept at \(pending.copy.path)")
    }

    /// From `applicationWillTerminate`: start the helper that opens the copy once we have exited.
    static func appWillTerminate() {
        guard let pending else { return }
        do {
            let work: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SpiderSolitaireMove-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let script: URL = work.appendingPathComponent("move.sh")
            try MoveScript.text.write(to: script, atomically: true, encoding: .utf8)
            let process: Process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments =
                [script.path]
                + MoveScript.arguments(
                    pid: ProcessInfo.processInfo.processIdentifier, copy: pending.copy.path,
                    original: pending.original.path, workFolder: work.path,
                    relaunch: DebugMoveTesting.relaunchCommand)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            DebugMoveTesting.log("helper started")
        } catch {
            show(
                "Spider Solitaire is in your Applications folder",
                "It couldn't be opened automatically. Open it from Applications. (\(error))")
        }
    }

    /// At launch: as the new copy, put the original in the Trash; as the original reopened after a
    /// failed move, say so (and keep running).
    static func handleLaunchNote() {
        switch MoveScript.launchNote(CommandLine.arguments) {
        case .movedFrom(let original)?:
            let info: NSDictionary? = NSDictionary(
                contentsOf: URL(fileURLWithPath: original).appendingPathComponent("Contents/Info.plist"))
            guard
                MoveScript.mayTrashOriginal(
                    original, runningApp: Bundle.main.bundleURL.path,
                    originalBundleIdentifier: info?["CFBundleIdentifier"] as? String)
            else { return }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: original), resultingItemURL: nil)
                DebugMoveTesting.log("original moved to the Trash: \(original)")
            } catch {
                DebugMoveTesting.log("original kept: \(error)")
            }
        case .moveFailed?:
            show(
                "Spider Solitaire couldn't be opened from Applications",
                "You're still using this copy. The copy in Applications was kept; open it from Finder to see "
                    + "what macOS reports, or drag it to the Trash.")
        case nil:
            break
        }
    }

    private static func show(_ title: String, _ message: String) {
        DebugMoveTesting.log("\(title): \(message)")
        guard !DebugMoveTesting.isActive else { return }
        let alert: NSAlert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

/// DEBUG builds only, for testing the move without /Applications: `SPIDER_MOVE_TEST_APPLICATIONS=<dir>`
/// is the Applications folder, the offer is accepted without asking, alerts are logged to stderr
/// instead, the store is a throwaway one, and `SPIDER_MOVE_TEST_RELAUNCH=/path/cmd` replaces
/// /usr/bin/open in the helper. Compiled out of release builds.
enum DebugMoveTesting {
    #if DEBUG
    private static let environment: [String: String] = ProcessInfo.processInfo.environment
    static let applications: URL? = environment["SPIDER_MOVE_TEST_APPLICATIONS"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
    static let relaunchCommand: String =
        (applications != nil ? environment["SPIDER_MOVE_TEST_RELAUNCH"] : nil) ?? "/usr/bin/open"
    static func log(_ value: String) {
        guard applications != nil || CommandLine.arguments.contains(MoveScript.movedFromArgument) else { return }
        FileHandle.standardError.write(Data("move: \(value)\n".utf8))
    }
    #else
    static let applications: URL? = nil
    static let relaunchCommand: String = "/usr/bin/open"
    static func log(_ value: String) {}
    #endif
    static var isActive: Bool { applications != nil }
}
#endif
