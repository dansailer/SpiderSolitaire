#if canImport(AppKit)
import AppKit
import Foundation
import SpiderUpdates

/// Once at launch: when the app runs from Downloads or translocated (where it can't update itself),
/// offer to move it to /Applications. Only when there is no copy there yet, so nothing is ever
/// replaced; "Don't ask again" stops the offer for good.
@MainActor
enum MoveToApplications {
    static let suppressKey: String = "SpiderSolitaireDontOfferMoveToApplications"
    static let applications: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)

    static func offerIfNeeded() {
        let app: URL = Bundle.main.bundleURL
        let destination: URL = applications.appendingPathComponent(app.lastPathComponent)
        guard
            AppLocation.shouldOfferMove(
                appPath: app.path, home: NSHomeDirectory(),
                suppressed: UserDefaults.standard.bool(forKey: suppressKey),
                applicationsCopyExists: FileManager.default.fileExists(atPath: destination.path))
        else { return }
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
        do {
            try move(app, to: destination)
        } catch {
            let failure: NSAlert = NSAlert()
            failure.messageText = "Spider Solitaire couldn't be moved"
            failure.informativeText =
                "Drag it to your Applications folder in Finder instead. (\(error.localizedDescription))"
            failure.runModal()
        }
    }

    /// Copies (never overwrites), drops the quarantine flag on the copy, moves the original to the
    /// Trash unless it is a read-only translocated path, opens the copy and quits.
    private static func move(_ app: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: app, to: destination)
        let xattr: Process = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try xattr.run()
        xattr.waitUntilExit()
        if !AppLocation.isTranslocated(app.path) {
            try? FileManager.default.trashItem(at: app, resultingItemURL: nil)
        }
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}
#endif
