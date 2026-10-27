#if canImport(SwiftUI)
import SpiderCore
import SwiftUI

/// M1 placeholder: draws the tableau as text cards and lets you deal / undo / start over.
/// Real rendering, drag and drop and XP styling arrive in M2-M7 (see MILESTONES.md).
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var game = SpiderGame(difficulty: .oneSuit, seed: UInt64.random(in: 0...UInt64.max))

    func newGame(_ difficulty: Difficulty) {
        game = SpiderGame(difficulty: difficulty, seed: UInt64.random(in: 0...UInt64.max))
    }

    func deal() { _ = try? game.perform(.deal) }
    func undo() { try? game.undo() }
}

struct BoardView: View {
    @StateObject private var model = GameModel()

    private static let felt = Color(red: 0, green: 0.5, blue: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<GameState.columnCount, id: \.self) { col in
                    VStack(spacing: -40) {
                        ForEach(model.game.state.columns[col]) { card in
                            CardPlaceholder(card: card)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            Spacer()
            HStack {
                Text("Completed: \(model.game.state.completed.count)/8")
                Spacer()
                Text("Score: \(model.game.state.score)   Moves: \(model.game.state.moves)")
                Spacer()
                Button("Deal (\(model.game.state.dealsRemaining))") { model.deal() }
                    .disabled(!model.game.state.canDeal)
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.game.canUndo)
                Menu("New Game") {
                    ForEach(Difficulty.allCases, id: \.self) { d in
                        Button(d.displayName) { model.newGame(d) }
                    }
                }
                .frame(width: 120)
            }
            .foregroundStyle(.white)
        }
        .padding()
        .background(Self.felt)
    }
}

private struct CardPlaceholder: View {
    let card: Card

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(card.isFaceUp ? Color.white : Color(red: 0.1, green: 0.2, blue: 0.6))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if card.isFaceUp {
                    Text(card.rank.label + card.suit.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(card.suit.isRed ? Color.red : Color.black)
                        .padding(3)
                }
            }
            .frame(width: 71, height: 96)
    }
}
#endif
