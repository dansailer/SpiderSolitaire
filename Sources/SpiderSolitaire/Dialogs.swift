#if canImport(SwiftUI)
import SpiderCore
import SwiftUI

/// XP "Difficulty" dialog: three radio buttons, OK starts a new game at that level.
struct DifficultySheet: View {
    @ObservedObject var model: GameModel
    @State private var selection: Difficulty

    init(model: GameModel) {
        self.model = model
        _selection = State<Difficulty>(initialValue: model.game.state.difficulty)
    }

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 14) {
            Text("Difficulty").font(Font.headline)
            Text("Select the game difficulty level that you want:")
            Picker("", selection: $selection) {
                ForEach(Difficulty.allCases, id: \.self) { (difficulty: Difficulty) in
                    Text(difficulty.displayName).tag(difficulty)
                }
            }
            .pickerStyle(RadioGroupPickerStyle())
            .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel", role: ButtonRole.cancel) { model.showDifficultySheet = false }
                    .keyboardShortcut(KeyboardShortcut.cancelAction)
                Button("OK") { model.chooseDifficulty(selection) }
                    .keyboardShortcut(KeyboardShortcut.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

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
            Text("Statistics").font(Font.headline)
            Picker("", selection: $difficulty) {
                ForEach(Difficulty.allCases, id: \.self) { (d: Difficulty) in
                    Text(d.displayName).tag(d)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            VStack(alignment: HorizontalAlignment.leading, spacing: 6) {
                StatRow(label: "Games played:", value: "\(stats.played)")
                StatRow(label: "Games won:", value: "\(stats.won)")
                StatRow(label: "Win percentage:", value: "\(stats.winPercentage)%")
                StatRow(label: "High score:", value: "\(stats.highScore)")
                Divider()
                StatRow(label: "Current streak:", value: currentStreak(stats))
                StatRow(label: "Longest winning streak:", value: "\(stats.longestWinStreak)")
                StatRow(label: "Longest losing streak:", value: "\(stats.longestLossStreak)")
            }

            HStack {
                Button("Reset") { model.resetStatistics(difficulty) }
                Spacer()
                Button("OK") { model.showStatisticsSheet = false }
                    .keyboardShortcut(KeyboardShortcut.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func currentStreak(_ stats: DifficultyStatistics) -> String {
        if stats.currentWinStreak > 0 { return "\(stats.currentWinStreak) win" + (stats.currentWinStreak == 1 ? "" : "s") }
        if stats.currentLossStreak > 0 { return "\(stats.currentLossStreak) loss" + (stats.currentLossStreak == 1 ? "" : "es") }
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

/// XP "Options" dialog plus this clone's extras (undo mode, animations).
struct OptionsSheet: View {
    @ObservedObject var model: GameModel
    @State private var draft: Options

    init(model: GameModel) {
        self.model = model
        _draft = State<Options>(initialValue: model.options)
    }

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 14) {
            Text("Options").font(Font.headline)

            Toggle("Show animations", isOn: $draft.animationsEnabled)
            Toggle("Play sounds", isOn: $draft.soundsEnabled)

            Text("Card faces")
            Picker("", selection: $draft.cardFaces) {
                Text("Classic (traditional English pattern)").tag(CardFaceStyle.classic)
                Text("Simple").tag(CardFaceStyle.simple)
            }
            .pickerStyle(RadioGroupPickerStyle())
            .labelsHidden()

            Text("Undo")
            Picker("", selection: $draft.undoPolicy) {
                Text("Unlimited (back to the start of the game)").tag(UndoPolicy.unlimited)
                Text("Classic XP (stops at deals and completed suits)").tag(UndoPolicy.xpClassic)
            }
            .pickerStyle(RadioGroupPickerStyle())
            .labelsHidden()

            Text("When the game is closed")
            Picker("", selection: $draft.saveOnExit) {
                Text("Always save the game").tag(ExitSavePolicy.always)
                Text("Never save the game (counts as a loss)").tag(ExitSavePolicy.never)
                Text("Prompt to save the game").tag(ExitSavePolicy.prompt)
            }
            .pickerStyle(RadioGroupPickerStyle())
            .labelsHidden()

            Text("When the game starts")
            Picker("", selection: $draft.openOnStart) {
                Text("Always open the saved game").tag(StartOpenPolicy.always)
                Text("Never open the saved game").tag(StartOpenPolicy.never)
                Text("Prompt to open the saved game").tag(StartOpenPolicy.prompt)
            }
            .pickerStyle(RadioGroupPickerStyle())
            .labelsHidden()

            HStack {
                Spacer()
                Button("Cancel", role: ButtonRole.cancel) { model.showOptionsSheet = false }
                    .keyboardShortcut(KeyboardShortcut.cancelAction)
                Button("OK") { model.applyOptions(draft) }
                    .keyboardShortcut(KeyboardShortcut.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
#endif
