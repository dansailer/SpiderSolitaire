#if canImport(SwiftUI)
import SpiderCore
import SwiftUI

/// XP "Statistics" dialog, one page per difficulty, with Reset.
struct StatisticsSheet: View {
    @ObservedObject var model: GameModel
    @State private var difficulty: Difficulty

    init(model: GameModel) {
        self.model = model
        _difficulty = State<Difficulty>(initialValue: model.game.state.difficulty)
    }

    var body: some View {
        let stats: DifficultyStatistics = model.statistics[difficulty]
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            Text(loc("Statistics")).font(Font.headline)
            Picker("", selection: $difficulty) {
                ForEach(Difficulty.allCases, id: \.self) { (d: Difficulty) in
                    Text(loc(d.displayName)).tag(d)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            VStack(alignment: HorizontalAlignment.leading, spacing: 6) {
                StatRow(label: loc("Games played:"), value: "\(stats.played)")
                StatRow(label: loc("Games won:"), value: "\(stats.won)")
                StatRow(label: loc("Win percentage:"), value: loc("%lld%%", stats.winPercentage))
                StatRow(label: loc("High score:"), value: "\(stats.highScore)")
                Divider()
                StatRow(label: loc("Current streak:"), value: currentStreak(stats))
                StatRow(label: loc("Longest winning streak:"), value: "\(stats.longestWinStreak)")
                StatRow(label: loc("Longest losing streak:"), value: "\(stats.longestLossStreak)")
            }

            HStack {
                Button(loc("Reset")) { model.resetStatistics(difficulty) }
                Spacer()
                Button(loc("OK")) { model.showStatisticsSheet = false }
                    .keyboardShortcut(KeyboardShortcut.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func currentStreak(_ stats: DifficultyStatistics) -> String {
        if stats.currentWinStreak > 0 {
            return loc("%lld wins", stats.currentWinStreak)
        }
        if stats.currentLossStreak > 0 {
            return loc("%lld losses", stats.currentLossStreak)
        }
        return "0"
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

#endif
