import Foundation

/// Where the project lives (Help ▸ Visit Website, update checks, the Settings credits).
public enum ProjectLinks {
    public static let owner: String = "dansailer"
    public static let repository: String = "SpiderSolitaire"
    public static let website: URL = URL(string: "https://dansailer.github.io/SpiderSolitaire/")!
    public static let sourceCode: URL = URL(string: "https://github.com/dansailer/SpiderSolitaire")!
    public static let latestReleasePage: URL = URL(string: "https://github.com/dansailer/SpiderSolitaire/releases/latest")!
    public static let latestReleaseAPI: URL = URL(string: "https://api.github.com/repos/dansailer/SpiderSolitaire/releases/latest")!
    /// The release asset the app downloads (scripts/package.sh and .github/workflows/release.yml).
    public static let assetName: String = "SpiderSolitaire.zip"
}

/// A semantic version (MAJOR.MINOR.PATCH, optional -prerelease), compared per semver.org §11.
/// Build metadata (+...) is ignored. A leading "v" (as in tag names) is accepted.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    public init(_ major: Int, _ minor: Int, _ patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Accepts "1", "1.2", "1.2.3", "v1.2.3", "1.2.3-beta.1", "1.2.3+build.5". Missing parts are 0.
    public init?(_ text: String) {
        var s: Substring = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        if let plus = s.firstIndex(of: "+") { s = s[..<plus] }
        var pre: [String] = []
        if let dash = s.firstIndex(of: "-") {
            pre = s[s.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !pre.isEmpty, pre.allSatisfy({ !$0.isEmpty }) else { return nil }
            s = s[..<dash]
        }
        let parts: [Substring] = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(numbers[0], numbers[1], numbers[2], prerelease: pre)
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        // A release is newer than any of its prereleases.
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true // numeric identifiers sort before alphanumeric ones
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}

/// The parts of GitHub's "latest release" JSON the app uses.
public struct ReleaseInfo: Decodable, Hashable, Sendable {
    public struct Asset: Decodable, Hashable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int?

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, htmlURL = "html_url", draft, prerelease, assets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try c.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    public static func decode(_ data: Data) throws -> ReleaseInfo {
        try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    public var version: SemanticVersion? { SemanticVersion(tagName) }

    /// The app zip, if the release has one.
    public var appAsset: Asset? { assets.first { $0.name == ProjectLinks.assetName } }
}

/// The result of comparing the running version with the latest release.
public enum UpdateStatus: Hashable, Sendable {
    case upToDate(current: SemanticVersion)
    case available(current: SemanticVersion, latest: SemanticVersion, release: ReleaseInfo)
    /// The running build has no usable version (e.g. `swift run`): any release counts as newer.
    case unknownCurrent(latest: SemanticVersion, release: ReleaseInfo)

    public static func evaluate(currentVersion: String?, release: ReleaseInfo) -> UpdateStatus? {
        guard !release.draft, !release.prerelease, let latest = release.version else { return nil }
        guard let text = currentVersion, let current = SemanticVersion(text) else {
            return .unknownCurrent(latest: latest, release: release)
        }
        return current < latest ? .available(current: current, latest: latest, release: release) : .upToDate(current: current)
    }

    public var isUpdate: Bool {
        if case .upToDate = self { return false }
        return true
    }
}

public enum UpdateCheckPolicy {
    public static let minimumInterval: TimeInterval = 24 * 60 * 60

    /// Automatic checks run at launch, at most once a day, when the setting is on.
    public static func shouldCheckAutomatically(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        // A clock set backwards must not block checks forever.
        return now.timeIntervalSince(lastCheck) >= minimumInterval || lastCheck > now
    }
}

public enum ReleaseNotes {
    /// The first lines of the Markdown release notes as plain text, for the update dialog:
    /// headings and list markers dropped, links reduced to their text, at most `limit` characters
    /// (cut at a word, with "…").
    public static func excerpt(_ markdown: String?, limit: Int = 600) -> String {
        guard let markdown else { return "" }
        var lines: [String] = []
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line: String = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("<!--") { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            if line.hasPrefix("* ") || line.hasPrefix("- ") { line = "• " + line.dropFirst(2) }
            line = stripLinks(line).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let text: String = lines.joined(separator: "\n")
        guard text.count > limit else { return text }
        let cut: Substring = text.prefix(limit)
        let end: String.Index = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cut.endIndex
        return String(cut[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// "[text](url)" → "text".
    static func stripLinks(_ line: String) -> String {
        var out: String = ""
        var rest: Substring = Substring(line)
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]"),
                  rest.index(after: close) < rest.endIndex, rest[rest.index(after: close)] == "(",
                  let paren = rest[close...].firstIndex(of: ")") else { break }
            out += rest[..<open]
            out += rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: paren)...]
        }
        return out + rest
    }
}

/// The request the app sends: unauthenticated, with a User-Agent (GitHub requires one) and the
/// API version header.
public enum UpdateRequest {
    public static let timeout: TimeInterval = 15

    public static func headers(appVersion: String?) -> [String: String] {
        [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "SpiderSolitaire/\(appVersion ?? "dev") (macOS; +\(ProjectLinks.sourceCode.absoluteString))",
        ]
    }

    /// A short, calm message for a failed check.
    public static func failureMessage(statusCode: Int?) -> String {
        switch statusCode {
        case 404?: return "No release has been published yet."
        case 403?, 429?: return "GitHub is limiting requests right now. Try again in an hour."
        case let code? where code >= 500: return "GitHub is not responding right now. Try again later."
        case .some: return "The update check failed. Try again later."
        case nil: return "Could not reach GitHub. Check your internet connection and try again."
        }
    }
}
