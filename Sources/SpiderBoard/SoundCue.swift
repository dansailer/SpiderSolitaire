/// Short system sounds (macOS built-ins only, no Microsoft assets). Off by default in Options.
public enum SoundCue: String, CaseIterable, Sendable {
    case deal, drop, cannotDeal, hint, noMoves, completedSuit, win

    /// Name of the macOS system sound (/System/Library/Sounds) played for this cue.
    public var systemSoundName: String {
        switch self {
        case .deal: return "Pop"
        case .drop: return "Tink"
        case .cannotDeal: return "Basso"
        case .hint: return "Ping"
        case .noMoves: return "Funk"
        case .completedSuit: return "Glass"
        case .win: return "Hero"
        }
    }

    /// Every sound name that ships with macOS 14 in /System/Library/Sounds.
    public static let macOSSystemSounds: Set<String> = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]
}
