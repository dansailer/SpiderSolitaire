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
}
