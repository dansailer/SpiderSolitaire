import Foundation
import SpiderCore
import SpiderUpdates
import XCTest

@testable import SpiderBoard

/// The app's string tables (Sources/SpiderSolitaire/Resources/Localization, SPEC.md §3.8): every
/// language has every key, formats keep their placeholders, and every text the app shows (its own
/// `loc("…")` keys and the shared modules' menu titles, help, achievements, credits and update
/// messages) has an entry. A new language is a new <language>.lproj folder; these tests then cover it.
final class LocalizationTests: XCTestCase {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let tables: URL = root.appendingPathComponent("Sources/SpiderSolitaire/Resources/Localization")
    static let appSources: URL = root.appendingPathComponent("Sources/SpiderSolitaire")
    /// Shown as is in every language.
    static let untranslated: Set<String> = ["Spider Solitaire"]

    static func languages() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: tables.path)
            .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }.sorted()
    }

    static func strings(_ language: String) throws -> [String: String] {
        let url: URL = tables.appendingPathComponent("\(language).lproj/Localizable.strings")
        return try StringsFile.parse(String(contentsOf: url, encoding: .utf8))
    }

    /// Plural entries: key → the plural variants ("one", "other"...) of its one variable.
    static func plurals(_ language: String) throws -> [String: [String: String]] {
        let url: URL = tables.appendingPathComponent("\(language).lproj/Localizable.stringsdict")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let plist: Any = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), options: [], format: nil)
        let root: [String: Any] = try XCTUnwrap(plist as? [String: Any])
        var result: [String: [String: String]] = [:]
        for (key, value) in root {
            let entry: [String: Any] = try XCTUnwrap(value as? [String: Any], key)
            let variables: [[String: Any]] = entry.values.compactMap { $0 as? [String: Any] }
            XCTAssertEqual(variables.count, 1, "\(language) \(key): one plural variable")
            var forms: [String: String] = [:]
            for (form, text) in variables.first ?? [:] where !form.hasPrefix("NSString") {
                forms[form] = text as? String
            }
            result[key] = forms
        }
        return result
    }

    func testEveryLanguageHasEveryKey() throws {
        let english: Set<String> = Set(try Self.strings("en").keys)
        let englishPlurals: Set<String> = Set(try Self.plurals("en").keys)
        XCTAssertFalse(english.isEmpty)
        let languages: [String] = try Self.languages()
        XCTAssertTrue(languages.contains("de"), "German is shipped")
        for language in languages where language != "en" {
            let keys: Set<String> = Set(try Self.strings(language).keys)
            XCTAssertEqual(english.subtracting(keys).sorted(), [], "missing in \(language).lproj")
            XCTAssertEqual(keys.subtracting(english).sorted(), [], "not in en.lproj (stale?) in \(language).lproj")
            let plurals: Set<String> = Set(try Self.plurals(language).keys)
            XCTAssertEqual(englishPlurals.subtracting(plurals).sorted(), [], "plurals missing in \(language).lproj")
            XCTAssertEqual(plurals.subtracting(englishPlurals).sorted(), [], "plurals not in en.lproj")
        }
    }

    func testEnglishEntriesAreTheirKeys() throws {
        for (key, value) in try Self.strings("en") {
            XCTAssertEqual(value, key, "en.lproj: the English text is the key")
        }
    }

    func testTranslationsKeepPlaceholders() throws {
        for language in try Self.languages() {
            for (key, value) in try Self.strings(language) {
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
                XCTAssertEqual(
                    try StringsFile.placeholders(value), try StringsFile.placeholders(key),
                    "\(language): \(key) → \(value)")
            }
            for (key, forms) in try Self.plurals(language) {
                XCTAssertNotNil(forms["one"], "\(language) \(key): one")
                XCTAssertNotNil(forms["other"], "\(language) \(key): other")
                for (form, text) in forms {
                    XCTAssertEqual(
                        try StringsFile.placeholders(text), try StringsFile.placeholders(key),
                        "\(language) \(key) \(form)")
                }
            }
        }
    }

    /// German typography: „…“ quotes and the … character, not ASCII stand-ins.
    func testGermanTypography() throws {
        let german: [String: String] = try Self.strings("de")
        for (key, value) in german {
            XCTAssertFalse(value.contains("\""), "de: straight quotes in \(key)")
            XCTAssertFalse(value.contains("..."), "de: three dots in \(key)")
            XCTAssertFalse(value.contains("“") && !value.contains("„"), "de: German quotes open with „ in \(key)")
        }
    }

    func testEveryAppKeyHasAnEntry() throws {
        let keys: Set<String> = try Self.keys("en")
        let used: [String] = try Self.appKeys()
        XCTAssertGreaterThan(used.count, 100, "the scanner finds the loc(\"…\") calls")
        XCTAssertEqual(used.filter { !keys.contains($0) }.sorted(), [], "loc(\"…\") keys missing from en.lproj")
    }

    func testEverySharedTextHasAnEntry() throws {
        let keys: Set<String> = try Self.keys("en")
        let missing: [String] = Set(Self.sharedTexts()).filter { !keys.contains($0) }.sorted()
        XCTAssertEqual(missing, [], "texts from SpiderCore / SpiderBoard / SpiderUpdates missing from en.lproj")
    }

    /// Every entry is used somewhere, so the tables don't collect stale texts.
    func testEveryEntryIsUsed() throws {
        let used: Set<String> = Set(try Self.appKeys()).union(Self.sharedTexts())
        let unused: [String] = try Self.keys("en").filter { !used.contains($0) }.sorted()
        XCTAssertEqual(unused, [], "entries in en.lproj that nothing shows")
    }

    /// UI text in the app goes through `loc`: no string literals straight into SwiftUI views or alerts.
    func testNoHardcodedUIText() throws {
        let pattern: NSRegularExpression = try NSRegularExpression(
            pattern:
                #"\b(Text|Button|Section|Picker|Link|Toggle|Label)\("([^"]*[a-z][^"]*)"|(messageText|informativeText|title) = "([^"]+)"|withTitle: "([^"]+)""#
        )
        var found: [String] = []
        for (file, text) in try Self.appSourceFiles() {
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let s: String = String(line)
                let range: NSRange = NSRange(s.startIndex..., in: s)
                for match in pattern.matches(in: s, range: range) {
                    let literal: String =
                        (2...5).compactMap { (i: Int) -> String? in
                            guard let r = Range(match.range(at: i), in: s), i != 3 else { return nil }
                            return String(s[r])
                        }.first ?? ""
                    if !Self.untranslated.contains(literal) {
                        found.append("\(file): \(s.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertEqual(found, [], "wrap these in loc(\"…\")")
    }

    // MARK: Helpers

    static func keys(_ language: String) throws -> Set<String> {
        Set(try strings(language).keys).union(try plurals(language).keys)
    }

    static func appSourceFiles() throws -> [(String, String)] {
        try FileManager.default.contentsOfDirectory(atPath: appSources.path).filter { $0.hasSuffix(".swift") }.sorted()
            .map { ($0, try String(contentsOf: appSources.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// The literal keys of every `loc("…")` call in the app (a literal may be split with `+`).
    static func appKeys() throws -> [String] {
        try appSourceFiles().flatMap { (_: String, text: String) -> [String] in
            let code: String = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            return StringsFile.locKeys(in: code)
        }
    }

    /// Texts the shared modules hand to the app for display. Strings without lowercase letters
    /// (shortcuts such as ⌘N, numbers such as +100) are shown as they are.
    static func sharedTexts() -> [String] {
        var texts: [String] = []
        for section in HelpContent.sections {
            texts.append(section.title)
            for block in section.blocks {
                switch block {
                case .heading(let text), .paragraph(let text): texts.append(text)
                case .bullets(let items): texts += items
                case .table(let header, let rows): texts += header + rows.flatMap { $0 }
                }
            }
        }
        for top in MenuBarLayout.menuBar {
            texts.append(top.title)
            for entry in MenuBarLayout.flatten(top.entries) {
                switch entry {
                case .command(let command): texts.append(command.title)
                case .standard(let item): texts.append(item.title)
                case .app(let item): texts.append(item.title)
                case .submenu(let menu, _): texts.append(menu.rawValue)
                case .services, .separator: break
                }
            }
        }
        texts += MenuCommand.allCases.map(\.title)
        for achievement in Achievement.all { texts += [achievement.title, achievement.hint] }
        texts += Difficulty.allCases.map(\.displayName)
        for credit in Credits.all { texts += [credit.title, credit.detail] + credit.links.map(\.title) }
        texts += [404, 403, 429, 500, 418, nil].map { UpdateRequest.failureMessage(statusCode: $0) }
        texts += [InstallPlan.notAnAppMessage, InstallPlan.translocatedMessage, InstallPlan.notWritableMessage]
        return texts.filter { (text: String) -> Bool in
            !untranslated.contains(text) && text.contains { $0.isLowercase }
        }
    }
}

/// A small reader for the `"key" = "value";` format of Localizable.strings (UTF-8, comments).
enum StringsFile {
    static func parse(_ text: String) throws -> [String: String] {
        var result: [String: String] = [:]
        var chars: [Character] = Array(text)
        var i: Int = 0
        func skipSpaceAndComments() {
            while i < chars.count {
                if chars[i].isWhitespace {
                    i += 1
                } else if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2
                } else if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                } else {
                    return
                }
            }
        }
        func quoted() throws -> String {
            guard i < chars.count, chars[i] == "\"" else { throw ParseError(offset: i) }
            i += 1
            var out: String = ""
            while i < chars.count, chars[i] != "\"" {
                if chars[i] == "\\", i + 1 < chars.count {
                    i += 1
                    switch chars[i] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(chars[i])
                    }
                } else {
                    out.append(chars[i])
                }
                i += 1
            }
            guard i < chars.count else { throw ParseError(offset: i) }
            i += 1
            return out
        }
        func expect(_ c: Character) throws {
            skipSpaceAndComments()
            guard i < chars.count, chars[i] == c else { throw ParseError(offset: i) }
            i += 1
        }
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        while true {
            skipSpaceAndComments()
            if i >= chars.count { break }
            let key: String = try quoted()
            try expect("=")
            skipSpaceAndComments()
            let value: String = try quoted()
            try expect(";")
            if result[key] != nil { throw ParseError(offset: i, duplicate: key) }
            result[key] = value
        }
        return result
    }

    struct ParseError: Error {
        let offset: Int
        var duplicate: String?
    }

    /// Format placeholders in order of their argument, ignoring positions (`%2$@` counts as `@`
    /// in second place), so a translation may reorder them.
    static func placeholders(_ text: String) throws -> [String] {
        let regex: NSRegularExpression = try NSRegularExpression(pattern: #"%(?:(\d+)\$)?(#@\w+@|lld|ld|d|@|%)"#)
        var positional: [(Int, String)] = []
        var next: Int = 1
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let spec: String = String(text[Range(match.range(at: 2), in: text)!])
            if spec == "%" { continue }
            if let r = Range(match.range(at: 1), in: text), let n = Int(text[r]) {
                positional.append((n, spec))
            } else {
                positional.append((next, spec))
                next += 1
            }
        }
        return positional.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Keys of `loc(` calls whose first argument is a string literal (or literals joined by `+`).
    static func locKeys(in source: String) -> [String] {
        let chars: [Character] = Array(source)
        var keys: [String] = []
        var i: Int = 0
        let marker: [Character] = Array("loc(")
        while i + marker.count < chars.count {
            guard Array(chars[i..<(i + marker.count)]) == marker,
                i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber)
            else {
                i += 1
                continue
            }
            var j: Int = i + marker.count
            var key: String = ""
            var sawLiteral: Bool = false
            while true {
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                guard j < chars.count, chars[j] == "\"" else { break }
                j += 1
                while j < chars.count, chars[j] != "\"" {
                    if chars[j] == "\\", j + 1 < chars.count {
                        j += 1
                        key.append(chars[j] == "n" ? "\n" : chars[j])
                    } else {
                        key.append(chars[j])
                    }
                    j += 1
                }
                j += 1
                sawLiteral = true
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                guard j < chars.count, chars[j] == "+" else { break }
                j += 1
            }
            if sawLiteral { keys.append(key) }
            i = j
        }
        return keys
    }
}
