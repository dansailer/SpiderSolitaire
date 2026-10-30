#if canImport(AppKit)
import Foundation
import SpiderBoard

/// User-facing text in the user's language (SPEC.md §3.8). The English text is the key: the
/// tables are Resources/Localization/<language>.lproj/Localizable.strings (and .stringsdict for
/// plurals) in the app's resource bundle. A missing translation shows the English text.
///
/// The shared modules (SpiderCore, SpiderBoard, SpiderUpdates) stay English and Foundation-free
/// where they are now; the app translates their texts (menu titles, help, achievements, credits,
/// update messages) where it shows them, so `loc(command.title)` works like `loc("New Game")`.
/// SpiderLocalizationTests checks that every such text and every `loc("…")` key has a translation.
enum Localization {
    /// The language in use: the first of the user's preferred languages (System Settings ▸
    /// General ▸ Language & Region, or the app's own language there) that the app has.
    static let language: String = {
        guard let bundle: Bundle = resourceBundle else { return "en" }
        let available: [String] = bundle.localizations.filter { $0 != "Base" }
        return Bundle.preferredLocalizations(from: available, forPreferences: Locale.preferredLanguages).first ?? "en"
    }()

    /// The `.lproj` folder of `language`. Chosen explicitly rather than through
    /// `Bundle.localizedString` on the resource bundle, which follows the main bundle's
    /// languages and so stays English when the app runs unbundled (`swift run`).
    private static let table: Bundle? = {
        guard let bundle: Bundle = resourceBundle,
            let path: String = bundle.path(forResource: language, ofType: "lproj")
        else { return nil }
        return Bundle(path: path)
    }()

    /// The SwiftPM resource bundle, found where the card faces are (see `ClassicCardImages`; not
    /// `Bundle.module`, which calls `fatalError` when the bundle is not where SwiftPM put it).
    private static let resourceBundle: Bundle? = {
        let candidates: [String] = ClassicCardArt.bundleCandidates(
            resourcePath: Bundle.main.resourceURL?.path,
            mainBundlePath: Bundle.main.bundleURL.path,
            executablePath: Bundle.main.executableURL?.resolvingSymlinksInPath().path)
        return candidates.lazy.compactMap { (path: String) -> Bundle? in Bundle(path: path) }.first
    }()

    static func string(_ key: String) -> String {
        table?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    /// Formats with the user's locale; plurals come from Localizable.stringsdict.
    static func string(_ key: String, arguments: [CVarArg]) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

/// The translation of `key`, an English text ("New Game").
func loc(_ key: String) -> String {
    Localization.string(key)
}

/// The translation of the format `key` ("Score: %lld"), filled in with `arguments`.
func loc(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.string(key, arguments: arguments)
}
#endif
