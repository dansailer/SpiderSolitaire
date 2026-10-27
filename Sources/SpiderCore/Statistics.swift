/// Per-difficulty record kept across launches (XP's Game > Statistics dialog).
public struct DifficultyStatistics: Codable, Sendable, Hashable {
    public var played = 0
    public var won = 0
    public var highScore = 0
    public var currentWinStreak = 0
    public var longestWinStreak = 0
    public var currentLossStreak = 0
    public var longestLossStreak = 0

    public init() {}

    /// Rounded to the nearest whole percent, as XP displays it.
    public var winPercentage: Int { played == 0 ? 0 : (won * 200 + played) / (played * 2) }

    public mutating func recordWin(score: Int) {
        played += 1
        won += 1
        highScore = max(highScore, score)
        currentWinStreak += 1
        currentLossStreak = 0
        longestWinStreak = max(longestWinStreak, currentWinStreak)
    }

    /// Called when a started game is abandoned (new game, quit without saving) or lost.
    public mutating func recordLoss() {
        played += 1
        currentLossStreak += 1
        currentWinStreak = 0
        longestLossStreak = max(longestLossStreak, currentLossStreak)
    }
}

public struct Statistics: Codable, Sendable, Hashable {
    public var byDifficulty: [Difficulty: DifficultyStatistics] = [:]

    public init() {}

    public subscript(difficulty: Difficulty) -> DifficultyStatistics {
        get { byDifficulty[difficulty] ?? DifficultyStatistics() }
        set { byDifficulty[difficulty] = newValue }
    }

    /// The Statistics dialog's Reset button: clears one difficulty.
    public mutating func reset(_ difficulty: Difficulty) {
        byDifficulty[difficulty] = nil
    }

    // JSON as {"1": {...}, "2": {...}, "4": {...}} (keyed by suit count) instead of Swift's
    // default array encoding for enum-keyed dictionaries.
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys {
            guard let raw = Int(key.stringValue), let difficulty = Difficulty(rawValue: raw) else { continue }
            byDifficulty[difficulty] = try container.decode(DifficultyStatistics.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (difficulty, stats) in byDifficulty {
            try container.encode(stats, forKey: Key(stringValue: String(difficulty.rawValue)))
        }
    }
}
