#if canImport(SwiftUI)
import AppKit
import Foundation
import SpiderUpdates
import SwiftUI

/// Spider Solitaire ▸ Check for Updates… and the once-a-day check at launch. Asks GitHub's public
/// "latest release" API (no account, no token), compares versions with `SpiderUpdates`, and shows
/// `UpdateView`. "Install" downloads the release zip and its SHA-256 file, checks the checksum,
/// unpacks it and checks the new app's Developer ID signature (`UpdateInstaller`), then offers
/// "Restart to Update": a small helper script swaps the bundle after the app has quit and relaunches
/// it. Where the app can't replace itself it falls back to saving the zip in Downloads.
@MainActor
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        /// Nothing in progress: before the first check, after Later, or after a cancelled download.
        case idle
        case checking
        case upToDate(version: String)
        case available(current: String, latest: String, notes: String, release: ReleaseInfo)
        /// `fraction` is nil until the size is known.
        case downloading(latest: String, fraction: Double?)
        case verifying(latest: String)
        case ready(latest: String)
        case installing(latest: String)
        /// The manual flow: the zip is in Downloads; `reason` says why it didn't install itself.
        case downloaded(file: URL, reason: String?)
        case failed(message: String)
        case installFailed(message: String, release: ReleaseInfo)

        var step: UpdateStep {
            switch self {
            case .idle: return .idle
            case .checking: return .checking
            case .upToDate: return .upToDate
            case .available: return .available
            case .downloading: return .downloading
            case .verifying: return .verifying
            case .ready: return .ready
            case .installing: return .installing
            case .downloaded: return .downloaded
            case .failed: return .failed
            case .installFailed: return .installFailed
            }
        }
    }

    @Published private(set) var phase: Phase = .idle {
        didSet {
            // Progress steps are not worth a log line each.
            if case .downloading(_, let fraction?) = phase, fraction < 1 { return }
            DebugUpdateTesting.log(phase)
        }
    }
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    /// A checked update waiting for "Restart to Update" (its folder is removed by Later or at quit).
    private var prepared: UpdateInstaller.Prepared?
    /// Set by "Restart to Update"; the helper starts in `applicationWillTerminate`.
    private var installOnQuit: Bool = false
    private static let lastCheckKey: String = "SpiderSolitaireLastUpdateCheck"

    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// At launch: at most once a day, and only shows a window when there is a new version.
    func checkAutomaticallyIfDue(enabled: Bool) {
        if DebugUpdateTesting.isActive {
            check(userInitiated: true)
            return
        }
        let last: Date? = UserDefaults.standard.object(forKey: UpdateController.lastCheckKey) as? Date
        guard UpdateCheckPolicy.shouldCheckAutomatically(enabled: enabled, lastCheck: last, now: Date()) else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !isBusyInstalling else {
            showWindow()
            return
        }
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
                if !DebugUpdateTesting.isActive {
                    UserDefaults.standard.set(Date(), forKey: UpdateController.lastCheckKey)
                }
                switch UpdateStatus.evaluate(currentVersion: UpdateController.currentVersion, release: release) {
                case .available(let current, let latest, let release)?:
                    self.phase = .available(
                        current: current.description, latest: latest.description,
                        notes: ReleaseNotes.excerpt(release.body), release: release)
                    self.showWindow()
                    if DebugUpdateTesting.autoInstall { self.install(release) }
                case .unknownCurrent(let latest, let release)?:
                    self.phase = .available(
                        current: loc("development build"), latest: latest.description,
                        notes: ReleaseNotes.excerpt(release.body), release: release)
                    if userInitiated { self.showWindow() }
                case .upToDate(let current)?:
                    self.phase = .upToDate(version: current.description)
                case nil:
                    self.phase = .upToDate(version: UpdateController.currentVersion ?? loc("this version"))
                }
            case .failure(let failure):
                self.phase = .failed(message: loc(UpdateRequest.failureMessage(statusCode: failure.statusCode)))
            }
        }
    }

    /// While a checked update waits or installs, a new check would only throw it away.
    private var isBusyInstalling: Bool { phase.step.keepsCurrentUpdate }

    struct UpdateFailure: Error {
        let statusCode: Int?
    }

    nonisolated static func fetchLatest() async -> Result<ReleaseInfo, UpdateFailure> {
        if let feed: URL = DebugUpdateTesting.feed {
            do {
                return .success(try ReleaseInfo.decode(try Data(contentsOf: feed)))
            } catch {
                return .failure(UpdateFailure(statusCode: 0))
            }
        }
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

    /// Release builds only fetch assets from this repository's GitHub releases.
    private static func isAllowedAssetURL(_ url: URL) -> Bool {
        UpdateTrust.isTrustedAssetURL(url) || (DebugUpdateTesting.isActive && url.isFileURL)
    }

    /// "Install": in place when the app can replace itself and the release is checkable,
    /// otherwise the manual Downloads flow with the reason. Without a zip asset, the release page.
    func install(_ release: ReleaseInfo) {
        guard let asset: ReleaseInfo.Asset = release.appAsset,
            UpdateController.isAllowedAssetURL(asset.browserDownloadURL)
        else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        let app: URL = Bundle.main.bundleURL
        switch UpdateInstaller.installPlan(for: app) {
        case .manual(let reason):
            downloadToDownloads(release, asset: asset, reason: loc(reason))
        case .inPlace(let target):
            guard let checksum: ReleaseInfo.Asset = release.checksumAsset,
                UpdateController.isAllowedAssetURL(checksum.browserDownloadURL)
            else {
                downloadToDownloads(
                    release, asset: asset,
                    reason: loc("This release has no checksum file, so it can't be installed automatically."))
                return
            }
            prepare(release, asset: asset, checksum: checksum, target: URL(fileURLWithPath: target))
        }
    }

    private func prepare(_ release: ReleaseInfo, asset: ReleaseInfo.Asset, checksum: ReleaseInfo.Asset, target: URL) {
        let latest: String = release.version?.description ?? release.tagName
        discardPrepared()
        phase = .downloading(latest: latest, fraction: nil)
        task = Task { @MainActor [weak self] in
            var work: URL?
            do {
                let folder: URL = try UpdateInstaller.makeWorkFolder(near: target)
                work = folder
                let zip: URL = try await UpdateController.fetch(
                    asset.browserDownloadURL, to: folder.appendingPathComponent(ProjectLinks.assetName)
                ) { [weak self] (fraction: Double) in
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(latest: latest, fraction: fraction)
                }
                let sums: URL = try await UpdateController.fetch(
                    checksum.browserDownloadURL, to: folder.appendingPathComponent(ProjectLinks.checksumAssetName),
                    progress: nil)
                try Task.checkCancellation()
                self?.phase = .verifying(latest: latest)
                let current: String? = UpdateController.currentVersion
                let newApp: URL = try await Task.detached(priority: TaskPriority.userInitiated) {
                    try UpdateInstaller.verifyChecksum(zip: zip, checksumFile: sums)
                    let app: URL = try UpdateInstaller.unzip(zip, into: folder.appendingPathComponent("new"))
                    try UpdateInstaller.verify(
                        app: app, bundleIdentifier: ProjectLinks.bundleIdentifier, currentVersion: current)
                    return app
                }.value
                try Task.checkCancellation()
                guard let self else { return }
                self.prepared = UpdateInstaller.Prepared(
                    version: latest, workFolder: folder, newApp: newApp, target: target)
                self.phase = .ready(latest: latest)
                self.showWindow()
                if DebugUpdateTesting.autoInstall {
                    if DebugUpdateTesting.takeLater() {
                        self.later()
                        self.check(userInitiated: true)
                    } else {
                        self.restartToUpdate()
                    }
                }
            } catch {
                if let work { try? FileManager.default.removeItem(at: work) }
                guard let self, !(error is CancellationError), !Task.isCancelled else { return }
                let message: String =
                    (error as? UpdateInstaller.Failure)?.description
                    ?? loc("The download failed. Check your internet connection and try again.")
                self.phase = .installFailed(message: message, release: release)
            }
        }
    }

    /// Downloads `url` to `destination`, reporting progress on the main actor.
    nonisolated private static func fetch(
        _ url: URL, to destination: URL, progress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws -> URL {
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 120)
        request.setValue(
            UpdateRequest.headers(appVersion: nil)["User-Agent"], forHTTPHeaderField: "User-Agent")
        let session: URLSession = URLSession(configuration: URLSessionConfiguration.ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let download: URLSessionDownloadTask = session.downloadTask(with: request) {
                    (temporary: URL?, response: URLResponse?, error: Error?) in
                    do {
                        if let error { throw error }
                        if let http: HTTPURLResponse = response as? HTTPURLResponse, http.statusCode != 200 {
                            throw URLError(URLError.Code.badServerResponse)
                        }
                        guard let temporary else { throw URLError(URLError.Code.cannotCreateFile) }
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        continuation.resume(returning: destination)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                if let progress {
                    observation = download.progress.observe(\Progress.fractionCompleted) {
                        (p: Progress, _: NSKeyValueObservedChange<Double>) in
                        let fraction: Double = p.fractionCompleted
                        Task { @MainActor in progress(fraction) }
                    }
                }
                download.resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    /// "Restart to Update": quit normally (the save prompt may still cancel), then the helper swaps
    /// the app once this process has exited.
    func restartToUpdate() {
        guard let prepared else { return }
        installOnQuit = true
        phase = .installing(latest: prepared.version)
        NSApplication.shared.terminate(nil)
    }

    /// The quit was cancelled (Cancel in "Do you want to save this game?"): keep the update ready.
    func quitWasCancelled() {
        guard installOnQuit, let prepared else { return }
        installOnQuit = false
        phase = .ready(latest: prepared.version)
    }

    /// From `applicationWillTerminate`: start the helper if armed, otherwise drop the staged files.
    func appWillTerminate() {
        if installOnQuit, let prepared {
            do {
                try UpdateInstaller.launchHelper(for: prepared, relaunch: DebugUpdateTesting.relaunchCommand)
                return
            } catch {
                DebugUpdateTesting.log("helper failed to start: \(error)")
            }
        }
        discardPrepared()
    }

    /// "Later": the checked update is thrown away; the next check offers it again.
    func later() {
        discardPrepared()
        phase = .idle
        close()
    }

    private func discardPrepared() {
        if let prepared { try? FileManager.default.removeItem(at: prepared.workFolder) }
        prepared = nil
        installOnQuit = false
    }

    /// The fallback: the zip into ~/Downloads, then show it in Finder.
    private func downloadToDownloads(_ release: ReleaseInfo, asset: ReleaseInfo.Asset, reason: String?) {
        let latest: String = release.version?.description ?? release.tagName
        phase = .downloading(latest: latest, fraction: nil)
        task = Task { @MainActor [weak self] in
            do {
                let temporary: URL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SpiderSolitaire-\(UUID().uuidString).zip")
                _ = try await UpdateController.fetch(asset.browserDownloadURL, to: temporary) {
                    [weak self] (fraction: Double) in
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(latest: latest, fraction: fraction)
                }
                let file: URL = try UpdateController.moveToDownloads(temporary, name: "SpiderSolitaire-\(latest).zip")
                guard let self else { return }
                self.phase = .downloaded(file: file, reason: reason)
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } catch {
                guard let self, !(error is CancellationError), !Task.isCancelled else { return }
                self.phase = .failed(
                    message: loc("The download failed. You can get the new version from the release page."))
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

    /// Cancel / Close / OK. A download in progress stops; a checked update stays ready until quit.
    func close() {
        task?.cancel()
        switch phase {
        case .downloading, .verifying: phase = .idle
        default: break
        }
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
                w.title = loc("Software Update")
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

/// DEBUG builds only, for testing updates end to end without publishing a release:
/// `SPIDER_UPDATE_TEST_FEED=/path/release.json` reads the "latest release" from that file (asset
/// URLs may be file:// URLs), checks at launch, keeps the app's real data untouched (throwaway
/// store, no last-check date) and logs each phase to stderr. `SPIDER_UPDATE_TEST_AUTO=1` also
/// presses Install and Restart to Update; `SPIDER_UPDATE_TEST_RELAUNCH=/path/cmd` replaces
/// /usr/bin/open for the relaunch. In release builds all of this is compiled out.
enum DebugUpdateTesting {
    #if DEBUG
    private static let environment: [String: String] = ProcessInfo.processInfo.environment
    static let feed: URL? = environment["SPIDER_UPDATE_TEST_FEED"].map { URL(fileURLWithPath: $0) }
    /// "1": Install, then Restart to Update. "later": Install, Later, a new check, then the same.
    static let autoInstall: Bool = feed != nil && ["1", "later"].contains(environment["SPIDER_UPDATE_TEST_AUTO"] ?? "")
    private static var laterPending: Bool = feed != nil && environment["SPIDER_UPDATE_TEST_AUTO"] == "later"
    static func takeLater() -> Bool {
        defer { laterPending = false }
        return laterPending
    }
    static let relaunchCommand: String =
        (feed != nil ? environment["SPIDER_UPDATE_TEST_RELAUNCH"] : nil) ?? "/usr/bin/open"
    static func log(_ value: Any) {
        guard feed != nil else { return }
        FileHandle.standardError.write(Data("update: \(value)\n".utf8))
    }
    #else
    static let feed: URL? = nil
    static let autoInstall: Bool = false
    static func takeLater() -> Bool { false }
    static let relaunchCommand: String = "/usr/bin/open"
    static func log(_ value: Any) {}
    #endif
    static var isActive: Bool { feed != nil }
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
        case .idle:
            Text(loc("No update in progress")).font(Font.headline)
            buttons(primary: (loc("OK"), { controller.close() }), secondary: nil)
        case .checking:
            Text(loc("Checking for updates…")).font(Font.headline)
            ProgressView().progressViewStyle(LinearProgressViewStyle())
            buttons(primary: nil, secondary: loc("Cancel"))
        case .upToDate(let version):
            Text(loc("You're up to date")).font(Font.headline)
            Text(loc("Spider Solitaire %@ is the newest version.", version))
                .foregroundColor(Color.secondary)
            buttons(primary: (loc("OK"), { controller.close() }), secondary: nil)
        case .available(let current, let latest, let notes, let release):
            Text(loc("Spider Solitaire %@ is available", latest)).font(Font.headline)
            Text(
                loc(
                    "You have %@. Install downloads and checks the new version; nothing changes until you restart.",
                    current)
            )
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
            Link(loc("View the release on GitHub"), destination: release.htmlURL)
                .font(Font.callout)
            buttons(primary: (loc("Install"), { controller.install(release) }), secondary: loc("Later"))
        case .downloading(let latest, let fraction):
            Text(loc("Downloading Spider Solitaire %@…", latest)).font(Font.headline)
            if let fraction {
                ProgressView(value: fraction).progressViewStyle(LinearProgressViewStyle())
            } else {
                ProgressView().progressViewStyle(LinearProgressViewStyle())
            }
            buttons(primary: nil, secondary: loc("Cancel"))
        case .verifying(let latest):
            Text(loc("Checking Spider Solitaire %@…", latest)).font(Font.headline)
            Text(loc("Making sure the download is complete and signed by its developer."))
                .foregroundColor(Color.secondary)
            ProgressView().progressViewStyle(LinearProgressViewStyle())
            buttons(primary: nil, secondary: loc("Cancel"))
        case .ready(let latest):
            Text(loc("Spider Solitaire %@ is ready to install", latest)).font(Font.headline)
            Text(
                loc(
                    "Restart to Update quits Spider Solitaire (you're asked about an unfinished game as usual), "
                        + "replaces it with the new version and opens it again.")
            )
            .foregroundColor(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(
                loc(
                    "Later keeps this version and deletes the download; you'll be offered the update at the next check."
                )
            )
            .font(Font.callout)
            .foregroundColor(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(loc("Later")) { controller.later() }
                    .keyboardShortcut(KeyboardShortcut.cancelAction)
                Button(loc("Restart to Update")) { controller.restartToUpdate() }
                    .keyboardShortcut(KeyboardShortcut.defaultAction)
            }
            .padding(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
        case .installing(let latest):
            Text(loc("Installing Spider Solitaire %@…", latest)).font(Font.headline)
            ProgressView().progressViewStyle(LinearProgressViewStyle())
        case .downloaded(let file, let reason):
            Text(loc("Downloaded")).font(Font.headline)
            if let reason {
                Text(reason)
                    .foregroundColor(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(
                loc(
                    "%@ is in your Downloads folder. Open it, then drag Spider Solitaire to Applications.",
                    file.lastPathComponent)
            )
            .foregroundColor(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            buttons(primary: (loc("Done"), { controller.close() }), secondary: nil)
        case .failed(let message):
            Text(loc("Couldn't check for updates")).font(Font.headline)
            Text(message)
                .foregroundColor(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons(primary: (loc("Try Again"), { controller.check(userInitiated: true) }), secondary: loc("Close"))
        case .installFailed(let message, let release):
            Text(loc("The update wasn't installed")).font(Font.headline)
            Text(loc("%@ Nothing was changed.", message))
                .foregroundColor(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(loc("Get it from the release page"), destination: release.htmlURL)
                .font(Font.callout)
            buttons(primary: (loc("Try Again"), { controller.install(release) }), secondary: loc("Close"))
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
