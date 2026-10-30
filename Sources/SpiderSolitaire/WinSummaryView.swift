#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore
import SwiftUI

/// How long the win panel takes to fade in.
enum WinPanelTiming {
    /// After the celebration has run to its end.
    static let afterShow: Double = 0.6
    /// After a click or key skipped the celebration.
    static let afterSkip: Double = 0.3
    /// With Reduce Motion on: the calm cross-fade that replaces the celebration.
    static let reduceMotion: Double = 1.0
}

/// "You win!" over the dimmed, finished board: this game's score, time and moves, the streaks at
/// this difficulty, a new high score, and what this game unlocked. Play Again (Return) deals a new
/// game; Close (Escape) leaves the finished board on screen.
struct WinSummaryOverlay: View {
    let summary: WinSummary
    let onPlayAgain: () -> Void
    let onClose: () -> Void

    static let gold: Color = Color(red: 0.80, green: 0.60, blue: 0.18)

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
            panel
        }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(Font.system(size: 34))
                    .foregroundStyle(WinSummaryOverlay.gold)
                    .accessibilityHidden(true)
                Text(loc("You win!"))
                    .font(Font.system(size: 26, weight: Font.Weight.bold, design: Font.Design.rounded))
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text(loc(summary.difficulty.displayName))
                    .font(Font.callout)
                    .foregroundColor(Color.secondary)
            }
            if summary.isNewHighScore {
                Label(loc("New high score"), systemImage: "star.fill")
                    .font(Font.callout.weight(Font.Weight.semibold))
                    .foregroundColor(Color(red: 0.45, green: 0.30, blue: 0.05))
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 12))
                    .background(
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.93, blue: 0.70))
                            .overlay(Capsule().stroke(WinSummaryOverlay.gold, lineWidth: 1))
                    )
            }
            HStack(spacing: 10) {
                WinStatTile(label: loc("Score"), value: summary.score.formatted())
                WinStatTile(label: loc("Time"), value: PlayClock.text(summary.seconds))
                WinStatTile(label: loc("Moves"), value: summary.moves.formatted())
            }
            VStack(spacing: 6) {
                StatRow(label: loc("Current streak:"), value: loc("%lld wins", summary.currentStreak))
                StatRow(label: loc("Longest winning streak:"), value: "\(summary.longestStreak)")
            }
            .accessibilityElement(children: AccessibilityChildBehavior.contain)
            if !summary.achievements.isEmpty {
                Divider()
                achievements
            }
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text(loc("Close")).frame(maxWidth: CGFloat.infinity)
                }
                .keyboardShortcut(KeyboardShortcut.cancelAction)
                Button(action: onPlayAgain) {
                    Text(loc("Play Again")).frame(maxWidth: CGFloat.infinity)
                }
                .keyboardShortcut(KeyboardShortcut.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(BoardView.felt)
            }
            .controlSize(ControlSize.large)
            .padding(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
        }
        .padding(EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: NSColor.windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WinSummaryOverlay.gold.opacity(0.7), lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 6)
        )
        .accessibilityElement(children: AccessibilityChildBehavior.contain)
        .accessibilityAddTraits(AccessibilityTraits.isModal)
        .accessibilityLabel(Text(loc("You win!")))
    }

    private var achievements: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 6) {
            Text(loc("Unlocked in this game"))
                .font(Font.caption.weight(Font.Weight.semibold))
                .foregroundColor(Color.secondary)
            // Two columns once there are several, so a first win's handful keeps the panel short.
            let columns: Int = summary.achievements.count > 3 ? 2 : 1
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(GridItem.Size.flexible(), spacing: 8, alignment: Alignment.leading),
                    count: columns),
                alignment: HorizontalAlignment.leading, spacing: 6
            ) {
                ForEach(summary.achievements, id: \.self) { (id: AchievementID) in
                    let achievement: Achievement = Achievement.with(id)
                    HStack(spacing: 8) {
                        BadgeView(emblem: achievement.emblem, unlocked: true, size: 26)
                        Text(loc(achievement.title))
                            .font(Font.callout.weight(Font.Weight.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: AccessibilityChildBehavior.combine)
                    .accessibilityLabel(Text(loc("Achievement unlocked: %@", loc(achievement.title))))
                }
            }
        }
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
    }
}

/// One big number with its label underneath (Score, Time, Moves).
struct WinStatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Font.system(size: 20, weight: Font.Weight.semibold, design: Font.Design.rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Font.caption)
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: CGFloat.infinity)
        .padding(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BoardView.felt.opacity(0.12))
        )
        .accessibilityElement(children: AccessibilityChildBehavior.ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}
#endif
