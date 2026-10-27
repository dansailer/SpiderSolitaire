import Foundation
import SpiderCore

/// JSON files in Application Support/SpiderSolitaire:
/// statistics.json, options.json, savedgame.json (the single XP save slot), achievements.json
/// (unlock dates) and winnable.json (winnable seeds found ahead of time).
public struct SpiderStore: Sendable {
    public static let folderName = "SpiderSolitaire"
    public static let statisticsFile = "statistics.json"
    public static let optionsFile = "options.json"
    public static let savedGameFile = "savedgame.json"
    public static let achievementsFile = "achievements.json"
    public static let winnableFile = "winnable.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/SpiderSolitaire on macOS (XDG data dir on Linux).
    public static func defaultDirectory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    public static func standard() -> SpiderStore { SpiderStore(directory: defaultDirectory()) }

    // MARK: Statistics and options (missing or unreadable files give defaults)

    public func loadStatistics() -> Statistics {
        (try? read(Statistics.self, SpiderStore.statisticsFile)) ?? Statistics()
    }
    public func saveStatistics(_ statistics: Statistics) throws { try write(statistics, SpiderStore.statisticsFile) }

    public func loadOptions() -> Options { (try? read(Options.self, SpiderStore.optionsFile)) ?? Options() }
    public func saveOptions(_ options: Options) throws { try write(options, SpiderStore.optionsFile) }

    public func loadAchievements() -> AchievementBook {
        (try? read(AchievementBook.self, SpiderStore.achievementsFile)) ?? AchievementBook()
    }
    public func saveAchievements(_ book: AchievementBook) throws { try write(book, SpiderStore.achievementsFile) }

    public func loadWinnableSeeds() -> WinnableSeedCache {
        (try? read(WinnableSeedCache.self, SpiderStore.winnableFile)) ?? WinnableSeedCache()
    }
    public func saveWinnableSeeds(_ cache: WinnableSeedCache) throws { try write(cache, SpiderStore.winnableFile) }

    // MARK: Saved game (one slot, like XP)

    public var hasSavedGame: Bool { FileManager.default.fileExists(atPath: url(SpiderStore.savedGameFile).path) }

    public func saveGame(_ session: SavedSession) throws { try write(session, SpiderStore.savedGameFile) }

    /// Reads the saved game without removing it. Nil if missing, corrupt or from a newer version.
    public func peekSavedGame() -> SavedSession? {
        guard let saved = try? read(SavedSession.self, SpiderStore.savedGameFile),
            saved.version <= SavedSession.currentVersion
        else { return nil }
        return saved
    }

    /// Opening a saved game uses it up (XP keeps one slot; this also stops replaying a save
    /// after losing). A corrupt file is removed too.
    public func takeSavedGame() -> SavedSession? {
        let saved = peekSavedGame()
        deleteSavedGame()
        return saved
    }

    public func deleteSavedGame() {
        try? FileManager.default.removeItem(at: url(SpiderStore.savedGameFile))
    }

    // MARK: Files

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let data = try Data(contentsOf: url(name))
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Atomic write (temp file + rename) so a crash mid-save never leaves half a file.
    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url(name), options: .atomic)
    }
}
