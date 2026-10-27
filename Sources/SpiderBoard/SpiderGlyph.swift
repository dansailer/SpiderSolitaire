/// The spider emblem used on the card back and the app icon, as plain geometry so SwiftUI and
/// CoreGraphics draw the same shape.
public enum SpiderGlyph {
    /// Abdomen (larger, lower) and head (smaller, upper) ellipses inside `rect`.
    public static func body(in rect: BoardRect) -> (abdomen: BoardRect, head: BoardRect) {
        let s = min(rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        let abdomen = BoardRect(x: cx - s * 0.16, y: cy - s * 0.06, width: s * 0.32, height: s * 0.38)
        let head = BoardRect(x: cx - s * 0.10, y: cy - s * 0.24, width: s * 0.20, height: s * 0.20)
        return (abdomen, head)
    }

    /// Eight legs, four per side, each a 3-point polyline (hip, knee, foot).
    public static func legs(in rect: BoardRect) -> [[BoardPoint]] {
        let s = min(rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        // (hip y, knee dx, knee dy, foot dx, foot dy) for the right side, as fractions of s.
        let right: [(Double, Double, Double, Double, Double)] = [
            (-0.12, 0.22, -0.30, 0.34, -0.46),
            (-0.06, 0.28, -0.12, 0.46, -0.20),
            (0.00, 0.28, 0.06, 0.46, 0.18),
            (0.06, 0.22, 0.24, 0.34, 0.44),
        ]
        var legs: [[BoardPoint]] = []
        for side in [1.0, -1.0] {
            for (hipY, kx, ky, fx, fy) in right {
                let hip = BoardPoint(x: cx + side * s * 0.06, y: cy + s * hipY)
                let knee = BoardPoint(x: cx + side * s * kx, y: cy + s * ky)
                let foot = BoardPoint(x: cx + side * s * fx, y: cy + s * fy)
                legs.append([hip, knee, foot])
            }
        }
        return legs
    }

    /// Leg stroke width for a glyph drawn in `rect`.
    public static func legWidth(in rect: BoardRect) -> Double { max(1, min(rect.width, rect.height) * 0.035) }
}

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
