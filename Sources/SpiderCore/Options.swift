/// XP Options dialog: what to do with an unfinished game when the app quits.
public enum ExitSavePolicy: String, Codable, Sendable, CaseIterable {
    case always, never, prompt
}

/// XP Options dialog: what to do with a saved game when the app starts.
public enum StartOpenPolicy: String, Codable, Sendable, CaseIterable {
    case always, never, prompt
}

/// User preferences, stored as options.json.
public struct Options: Codable, Sendable, Hashable {
    public var difficulty: Difficulty = .oneSuit
    public var undoPolicy: UndoPolicy = .unlimited
    public var animationsEnabled: Bool = true
    public var saveOnExit: ExitSavePolicy = .always
    public var openOnStart: StartOpenPolicy = .always

    public init() {}

    // Tolerant decoding: a missing or unknown field falls back to its default, so adding options
    // later never throws away a user's settings file.
    private enum CodingKeys: String, CodingKey {
        case difficulty, undoPolicy, animationsEnabled, saveOnExit, openOnStart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Options()
        difficulty = (try? c.decode(Difficulty.self, forKey: .difficulty)) ?? d.difficulty
        undoPolicy = (try? c.decode(UndoPolicy.self, forKey: .undoPolicy)) ?? d.undoPolicy
        animationsEnabled = (try? c.decode(Bool.self, forKey: .animationsEnabled)) ?? d.animationsEnabled
        saveOnExit = (try? c.decode(ExitSavePolicy.self, forKey: .saveOnExit)) ?? d.saveOnExit
        openOnStart = (try? c.decode(StartOpenPolicy.self, forKey: .openOnStart)) ?? d.openOnStart
    }
}
