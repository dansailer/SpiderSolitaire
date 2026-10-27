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

/// Spider Solitaire ▸ Settings… (⌘,): XP's Options plus this clone's extras. As in other Mac
/// apps, changes apply at once (no OK/Cancel).
struct SettingsView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Form {
            Section {
                Toggle("Show animations", isOn: binding(\Options.animationsEnabled))
                Toggle("Play sounds", isOn: binding(\Options.soundsEnabled))
                Toggle(isOn: binding(\Options.winnableDealsOnly)) {
                    Text("Only deal winnable games")
                    Text("New games use deals a solver has proved can be won.")
                }
            }
            Section("Card faces") {
                Picker("Card faces", selection: binding(\Options.cardFaces)) {
                    Text("Classic (traditional English pattern)").tag(CardFaceStyle.classic)
                    Text("Simple").tag(CardFaceStyle.simple)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
            Section("Undo") {
                Picker("Undo", selection: binding(\Options.undoPolicy)) {
                    Text("Unlimited (back to the start of the game)").tag(UndoPolicy.unlimited)
                    Text("Classic XP (stops at deals and completed suits)").tag(UndoPolicy.xpClassic)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
            Section("When the game is closed") {
                Picker("When the game is closed", selection: binding(\Options.saveOnExit)) {
                    Text("Always save the game").tag(ExitSavePolicy.always)
                    Text("Never save the game (counts as a loss)").tag(ExitSavePolicy.never)
                    Text("Prompt to save the game").tag(ExitSavePolicy.prompt)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
            Section("When the game starts") {
                Picker("When the game starts", selection: binding(\Options.openOnStart)) {
                    Text("Always open the saved game").tag(StartOpenPolicy.always)
                    Text("Never open the saved game").tag(StartOpenPolicy.never)
                    Text("Prompt to open the saved game").tag(StartOpenPolicy.prompt)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
        }
        .formStyle(GroupedFormStyle())
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Options, Value>) -> Binding<Value> {
        Binding<Value>(
            get: { model.options[keyPath: keyPath] },
            set: { (value: Value) in
                var options: Options = model.options
                options[keyPath: keyPath] = value
                model.applyOptions(options)
            }
        )
    }
}
#endif
