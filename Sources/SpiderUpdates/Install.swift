import Foundation

/// Reads the `SpiderSolitaire.zip.sha256` release asset (`shasum -a 256` output).
public enum UpdateChecksum {
    /// The lowercase hex SHA-256 for `fileName`: accepts "HEX  name", "HEX *name" (binary mode)
    /// and a bare "HEX". A line naming another file, or anything that is not 64 hex digits, is nil.
    public static func parse(_ text: String, fileName: String = ProjectLinks.assetName) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts: [Substring] = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            let hex: String = String(parts[0]).lowercased()
            guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
            if parts.count == 2 {
                var name: Substring = parts[1].drop(while: { $0 == " " || $0 == "\t" })
                if name.first == "*" { name = name.dropFirst() }
                guard name == fileName || name.hasSuffix("/" + fileName) else { continue }
            }
            return hex
        }
        return nil
    }

    /// Lowercase hex of a digest.
    public static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { (byte: UInt8) -> String in
            let digits: String = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }

    /// Constant-time-ish comparison of two hex digests (case-insensitive).
    public static func matches(_ a: String, _ b: String) -> Bool {
        let x: [UInt8] = Array(a.lowercased().utf8)
        let y: [UInt8] = Array(b.lowercased().utf8)
        guard x.count == 64, x.count == y.count else { return false }
        var diff: UInt8 = 0
        for (p, q) in zip(x, y) { diff |= p ^ q }
        return diff == 0
    }
}

/// What a downloaded app must be before it may replace the running one.
public enum UpdateTrust {
    /// Code signing requirement for `SecStaticCodeCheckValidity`: signed through Apple's CA with a
    /// Developer ID Application certificate (the 6.1.13 leaf marker, 6.2.6 intermediate marker)
    /// of our team, and with our bundle identifier as the signing identifier.
    public static func requirement(
        bundleIdentifier: String = ProjectLinks.bundleIdentifier,
        teamIdentifier: String = ProjectLinks.teamIdentifier
    ) -> String {
        "anchor apple generic"
            + " and identifier \"\(bundleIdentifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// Only strictly newer versions install; an unknown running version (a development build)
    /// never installs in place.
    public static func isNewer(candidate: String?, than current: String?) -> Bool {
        guard let candidate, let new = SemanticVersion(candidate), let current, let old = SemanticVersion(current)
        else { return false }
        return old < new
    }

    /// Release builds only download from this repository's release assets over https.
    public static func isTrustedAssetURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.absoluteString.hasPrefix(ProjectLinks.releaseDownloadPrefix)
            && !url.absoluteString.contains("/../")
    }
}

/// Where the running app is and whether it can replace itself there.
public enum AppLocation {
    /// Gatekeeper's App Translocation runs quarantined apps opened from where they were downloaded
    /// from a random read-only path like /private/var/folders/…/AppTranslocation/<UUID>/d/X.app.
    public static func isTranslocated(_ appPath: String) -> Bool {
        appPath.contains("/AppTranslocation/")
    }

    /// The app sits in ~/Downloads (or a folder in it).
    public static func isInDownloads(_ appPath: String, home: String) -> Bool {
        let downloads: String = (home.hasSuffix("/") ? String(home.dropLast()) : home) + "/Downloads/"
        return appPath.hasPrefix(downloads)
    }

    public static func isInApplications(_ appPath: String, home: String) -> Bool {
        let trimmedHome: String = home.hasSuffix("/") ? String(home.dropLast()) : home
        return appPath.hasPrefix("/Applications/") || appPath.hasPrefix(trimmedHome + "/Applications/")
    }

    /// Offer "Move to Applications" at launch: the app runs translocated or from Downloads, the
    /// user has not said "don't ask again", and there is no copy in the Applications folder yet
    /// (replacing one would need its own confirmation, so we leave that to the user).
    public static func shouldOfferMove(
        appPath: String, home: String, suppressed: Bool, applicationsCopyExists: Bool
    ) -> Bool {
        guard !suppressed, appPath.hasSuffix(".app"), !applicationsCopyExists else { return false }
        return isTranslocated(appPath) || isInDownloads(appPath, home: home)
    }
}

/// How a verified update gets installed.
public enum InstallPlan: Hashable, Sendable {
    /// Swap the bundle at `target` once the app has quit, then relaunch it.
    case inPlace(target: String)
    /// Save the zip to Downloads and show it in Finder; `reason` is shown to the user.
    case manual(reason: String)

    public static let notAnAppMessage: String =
        "This copy of Spider Solitaire isn't an installed app, so it can't update itself."
    public static let translocatedMessage: String =
        "Spider Solitaire is running from a temporary location macOS uses for apps opened from Downloads, "
        + "so it can't update itself. Move it to your Applications folder first."
    public static let notWritableMessage: String =
        "Spider Solitaire can't write to the folder it is in, so it can't update itself."

    public static func decide(appPath: String, parentWritable: Bool) -> InstallPlan {
        guard appPath.hasSuffix(".app") else { return .manual(reason: notAnAppMessage) }
        if AppLocation.isTranslocated(appPath) { return .manual(reason: translocatedMessage) }
        guard parentWritable else { return .manual(reason: notWritableMessage) }
        return .inPlace(target: appPath)
    }
}

/// The helper that swaps the app bundle after the app has quit. A /bin/sh script (no extra binary
/// to sign); `arguments` are passed positionally, never interpolated into the script text.
public enum InstallScript {
    public static let text: String = """
        #!/bin/sh
        # Spider Solitaire updater: $1 pid to wait for, $2 installed app, $3 new app, $4 backup path,
        # $5 work folder (removed on success), $6 relaunch command (normally /usr/bin/open).
        pid="$1"; target="$2"; new="$3"; backup="$4"; work="$5"; relaunch="$6"
        log="$work/install.log"
        n=0
        while kill -0 "$pid" 2>/dev/null; do
            n=$((n + 1))
            if [ "$n" -gt 600 ]; then echo "app did not quit" >> "$log"; exit 1; fi
            sleep 0.1
        done
        if [ ! -d "$new" ]; then echo "new app missing" >> "$log"; "$relaunch" "$target"; exit 1; fi
        if ! mv "$target" "$backup" 2>> "$log"; then
            echo "could not move the old app aside" >> "$log"; "$relaunch" "$target"; exit 1
        fi
        if ! mv "$new" "$target" 2>> "$log"; then
            echo "could not move the new app in, rolling back" >> "$log"
            mv "$backup" "$target" 2>> "$log"
            "$relaunch" "$target"; exit 1
        fi
        xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
        "$relaunch" "$target"
        rm -rf "$work"
        exit 0

        """

    public static func arguments(
        pid: Int32, target: String, newApp: String, backup: String, workFolder: String,
        relaunch: String = "/usr/bin/open"
    ) -> [String] {
        [String(pid), target, newApp, backup, workFolder, relaunch]
    }
}
