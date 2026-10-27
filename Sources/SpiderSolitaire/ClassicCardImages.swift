#if canImport(AppKit)
import AppKit
import SpiderBoard
import SpiderCore

/// Loads and caches the Classic card face PNGs from the app's resource bundle.
///
/// Deliberately not `Bundle.module`: SwiftPM's generated accessor looks next to the executable's
/// bundle root (`X.app/SpiderSolitaire_SpiderSolitaire.bundle`) and then the absolute build folder,
/// and calls `fatalError` if neither exists. A signed .app keeps the bundle in Contents/Resources,
/// so we search there first and simply fall back to the code-drawn faces when nothing is found.
final class ClassicCardImages: @unchecked Sendable {
    static let shared: ClassicCardImages = ClassicCardImages()

    private let lock: NSLock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var missing: Set<String> = []
    private let bundlePaths: [String]

    init() {
        let candidates: [String] = ClassicCardArt.bundleCandidates(
            resourcePath: Bundle.main.resourceURL?.path,
            mainBundlePath: Bundle.main.bundleURL.path,
            executablePath: Bundle.main.executableURL?.resolvingSymlinksInPath().path)
        var isDirectory: ObjCBool = false
        bundlePaths = candidates.filter { (path: String) -> Bool in
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The image for a face-up card, or nil (then CardView draws the simple face).
    func image(for card: Card) -> NSImage? {
        let name: String = ClassicCardArt.assetName(for: card)
        lock.lock()
        defer { lock.unlock() }
        if let cached: NSImage = cache[name] { return cached }
        if missing.contains(name) { return nil }
        for bundlePath in bundlePaths {
            for path in ClassicCardArt.imagePathCandidates(bundlePath: bundlePath, assetName: name) {
                if let image: NSImage = NSImage(contentsOfFile: path) {
                    cache[name] = image
                    return image
                }
            }
        }
        missing.insert(name)
        return nil
    }
}
#endif
