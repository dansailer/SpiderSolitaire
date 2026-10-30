#if canImport(SwiftUI)
import AppKit
import Foundation
import SpiderBoard
import SpiderCore
import SwiftUI

/// One badge, drawn from `BadgeArt` (the same art as the Linux previews).
struct BadgeView: View {
    let emblem: AchievementEmblem
    let unlocked: Bool
    let size: CGFloat

    var body: some View {
        VectorSceneView(scene: BadgeArt.scene(emblem, unlocked: unlocked, size: Double(size)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Banner that slides in at the top of the board when an achievement unlocks.
struct AchievementToastView: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 10) {
            BadgeView(emblem: achievement.emblem, unlocked: true, size: 40)
            VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                Text(loc("Achievement unlocked"))
                    .font(Font.caption)
                    .foregroundColor(Color(red: 0.45, green: 0.30, blue: 0.05))
                Text(loc(achievement.title))
                    .font(Font.headline)
                    .foregroundColor(Color.black)
                Text(loc(achievement.hint))
                    .font(Font.caption)
                    .foregroundColor(Color(white: 0.3))
                    .lineLimit(2)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 16))
        .frame(maxWidth: 380, alignment: Alignment.leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 1.0, green: 0.98, blue: 0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.80, green: 0.60, blue: 0.18), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
        )
        .accessibilityElement(children: AccessibilityChildBehavior.combine)
        .accessibilityLabel(Text(loc("Achievement unlocked: %@", loc(achievement.title))))
    }
}

/// "Dealing a winnable game…" with a Cancel button, over a dimmed board that ignores clicks.
struct DealingOverlay: View {
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(ControlSize.regular)
                Text(loc("Dealing a winnable game…"))
                    .font(Font.headline)
                Button(loc("Cancel")) { onCancel() }
                    .keyboardShortcut(KeyboardShortcut.cancelAction)
            }
            .padding(EdgeInsets(top: 18, leading: 26, bottom: 16, trailing: 26))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
            )
        }
    }
}

/// The Achievements window: every badge, gold with its date once unlocked, grey with its hint before.
struct AchievementsView: View {

    @ObservedObject var model: GameModel

    var body: some View {
        let book: AchievementBook = model.achievements
        let unlockedCount: Int = Achievement.all.filter { (a: Achievement) -> Bool in book.isUnlocked(a.id) }.count
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            Text(loc("%lld of %lld unlocked", unlockedCount, Achievement.all.count))
                .font(Font.headline)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(GridItem.Size.adaptive(minimum: 150, maximum: 200), spacing: 14)], spacing: 18
                ) {
                    ForEach(Achievement.all) { (achievement: Achievement) in
                        AchievementTile(achievement: achievement, unlockedAt: book.unlocked[achievement.id])
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 2, bottom: 8, trailing: 2))
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 720, minHeight: 420, idealHeight: 560)
    }
}

struct AchievementTile: View {
    let achievement: Achievement
    /// Seconds since 1970, nil while locked.
    let unlockedAt: Double?

    var body: some View {
        let unlocked: Bool = unlockedAt != nil
        VStack(spacing: 6) {
            BadgeView(emblem: achievement.emblem, unlocked: unlocked, size: 84)
            Text(loc(achievement.title))
                .font(Font.headline)
                .foregroundColor(unlocked ? Color.primary : Color.secondary)
            Text(loc(achievement.hint))
                .font(Font.caption)
                .foregroundColor(Color.secondary)
                .multilineTextAlignment(TextAlignment.center)
                .fixedSize(horizontal: false, vertical: true)
            if let unlockedAt {
                Text(
                    loc(
                        "Unlocked %@",
                        Date(timeIntervalSince1970: unlockedAt).formatted(
                            date: Date.FormatStyle.DateStyle.abbreviated,
                            time: Date.FormatStyle.TimeStyle.omitted))
                )
                .font(Font.caption.weight(Font.Weight.semibold))
                .foregroundColor(Color(red: 0.55, green: 0.38, blue: 0.05))
            }
        }
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.top)
        .padding(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
        .accessibilityElement(children: AccessibilityChildBehavior.combine)
    }
}
#endif
