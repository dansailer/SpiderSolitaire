#if canImport(SwiftUI)
import AppKit
import Foundation
import SpiderUpdates
import SwiftUI

/// Spider Solitaire ▸ Check for Updates… and the once-a-day check at launch. Asks GitHub's public
/// "latest release" API (no account, no token), compares versions with `SpiderUpdates`, and shows
/// `UpdateView`. It never replaces the app itself: that needs Developer ID signing and Sparkle.
@MainActor
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        case checking
        case upToDate(version: String)
        case available(current: String, latest: String, notes: String, release: ReleaseInfo)
        case downloading(latest: String)
        case downloaded(file: URL)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .checking
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private static let lastCheckKey: String = "SpiderSolitaireLastUpdateCheck"

    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// At launch: at most once a day, and only shows a window when there is a new version.
    func checkAutomaticallyIfDue(enabled: Bool) {
        let last: Date? = UserDefaults.standard.object(forKey: UpdateController.lastCheckKey) as? Date
        guard UpdateCheckPolicy.shouldCheckAutomatically(enabled: enabled, lastCheck: last, now: Date()) else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        task?.cancel()
        if userInitiated {
            phase = .checking
            showWindow()
        }
        task = Task { @MainActor [weak self] in
            let result: Result<ReleaseInfo, UpdateFailure> = await UpdateController.fetchLatest()
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let release):
                UserDefaults.standard.set(Date(), forKey: UpdateController.lastCheckKey)
                switch UpdateStatus.evaluate(currentVersion: UpdateController.currentVersion, release: release) {
                case .available(let current, let latest, let release)?:
                    self.phase = .available(
                        current: current.description, latest: latest.description,
                        notes: ReleaseNotes.excerpt(release.body), release: release)
                    self.showWindow()
                case .unknownCurrent(let latest, let release)?:
                    self.phase = .available(
                        current: "development build", latest: latest.description,
                        notes: ReleaseNotes.excerpt(release.body), release: release)
                    if userInitiated { self.showWindow() }
                case .upToDate(let current)?:
                    self.phase = .upToDate(version: current.description)
                case nil:
                    self.phase = .upToDate(version: UpdateController.currentVersion ?? "this version")
                }
            case .failure(let failure):
                self.phase = .failed(message: UpdateRequest.failureMessage(statusCode: failure.statusCode))
            }
        }
    }

    struct UpdateFailure: Error {
        let statusCode: Int?
    }

    nonisolated static func fetchLatest() async -> Result<ReleaseInfo, UpdateFailure> {
        var request: URLRequest = URLRequest(
            url: ProjectLinks.latestReleaseAPI,
            cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalCacheData,
            timeoutInterval: UpdateRequest.timeout)
        for (field, value) in UpdateRequest.headers(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let session: URLSession = URLSession(configuration: URLSessionConfiguration.ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response): (Data, URLResponse) = try await session.data(for: request)
            let status: Int = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(UpdateFailure(statusCode: status)) }
            return .success(try ReleaseInfo.decode(data))
        } catch is DecodingError {
            return .failure(UpdateFailure(statusCode: 0))
        } catch {
            return .failure(UpdateFailure(statusCode: nil))
        }
    }

    /// Download: the zip into ~/Downloads, then show it in Finder. Without a zip asset, the release page.
    func download(_ release: ReleaseInfo) {
        guard let asset: ReleaseInfo.Asset = release.appAsset else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        let latest: String = release.version?.description ?? release.tagName
        phase = .downloading(latest: latest)
        task = Task { @MainActor [weak self] in
            do {
                var request: URLRequest = URLRequest(url: asset.browserDownloadURL, timeoutInterval: 120)
                request.setValue(
                    UpdateRequest.headers(appVersion: UpdateController.currentVersion)["User-Agent"],
                    forHTTPHeaderField: "User-Agent")
                let (temporary, response): (URL, URLResponse) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(URLError.Code.badServerResponse)
                }
                let file: URL = try UpdateController.moveToDownloads(temporary, name: "SpiderSolitaire-\(latest).zip")
                guard let self else { return }
                self.phase = .downloaded(file: file)
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } catch {
                guard let self else { return }
                self.phase = .failed(message: "The download failed. You can get the new version from the release page.")
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private static func moveToDownloads(_ temporary: URL, name: String) throws -> URL {
        let manager: FileManager = FileManager.default
        let downloads: URL = try manager.url(
            for: FileManager.SearchPathDirectory.downloadsDirectory,
            in: FileManager.SearchPathDomainMask.userDomainMask,
            appropriateFor: nil, create: true)
        var target: URL = downloads.appendingPathComponent(name)
        var n: Int = 2
        while manager.fileExists(atPath: target.path) {
            target = downloads.appendingPathComponent(name.replacingOccurrences(of: ".zip", with: " \(n).zip"))
            n += 1
        }
        try manager.moveItem(at: temporary, to: target)
        return target
    }

    func close() {
        task?.cancel()
        window?.close()
    }

    private func showWindow() {
        let window: NSWindow =
            self.window
            ?? {
                let controller: NSHostingController<UpdateView> = NSHostingController<UpdateView>(
                    rootView: UpdateView(controller: self))
                controller.sizingOptions = [NSHostingSizingOptions.preferredContentSize]
                let w: NSWindow = NSWindow(contentViewController: controller)
                w.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
                w.title = "Software Update"
                w.isReleasedWhenClosed = false
                w.tabbingMode = NSWindow.TabbingMode.disallowed
                w.collectionBehavior.insert(NSWindow.CollectionBehavior.fullScreenNone)
                w.center()
                return w
            }()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

/// The update window: app icon, what was found, the release notes excerpt, and the buttons.
struct UpdateView: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        HStack(alignment: VerticalAlignment.top, spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: HorizontalAlignment.leading, spacing: 10) {
                content
            }
            .frame(width: 340, alignment: Alignment.leading)
        }
        .padding(20)
        .animation(Animation.easeOut(duration: 0.2), value: controller.phase)
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .checking:
            Text("Checking for updates…").font(Font.headline)
            ProgressView().progressViewStyle(LinearProgressViewStyle())
            buttons(primary: nil, secondary: "Cancel")
        case .upToDate(let version):
            Text("You're up to date").font(Font.headline)
            Text("Spider Solitaire \(version) is the newest version.")
                .foregroundColor(Color.secondary)
            buttons(primary: ("OK", { controller.close() }), secondary: nil)
        case .available(let current, let latest, let notes, let release):
            Text("Spider Solitaire \(latest) is available").font(Font.headline)
            Text("You have \(current). Download the new version, then replace the app in your Applications folder.")
                .foregroundColor(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(Font.callout)
                        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            Link("View the release on GitHub", destination: release.htmlURL)
                .font(Font.callout)
            buttons(primary: ("Download", { controller.download(release) }), secondary: "Later")
        case .downloading(let latest):
            Text("Downloading Spider Solitaire \(latest)…").font(Font.headline)
            ProgressView().progressViewStyle(LinearProgressViewStyle())
            buttons(primary: nil, secondary: "Cancel")
        case .downloaded(let file):
            Text("Downloaded").font(Font.headline)
            Text(
                "\(file.lastPathComponent) is in your Downloads folder. Open it, then drag Spider Solitaire to Applications."
            )
            .foregroundColor(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            buttons(primary: ("Done", { controller.close() }), secondary: nil)
        case .failed(let message):
            Text("Couldn't check for updates").font(Font.headline)
            Text(message)
                .foregroundColor(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons(primary: ("Try Again", { controller.check(userInitiated: true) }), secondary: "Close")
        }
    }

    private func buttons(primary: (String, () -> Void)?, secondary: String?) -> some View {
        HStack {
            Spacer()
            if let secondary {
                Button(secondary) { controller.close() }
                    .keyboardShortcut(KeyboardShortcut.cancelAction)
            }
            if let primary {
                Button(primary.0, action: primary.1)
                    .keyboardShortcut(KeyboardShortcut.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
    }
}
#endif
