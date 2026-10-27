#if canImport(SwiftUI)
import SpiderBoard
import SpiderCore
import SwiftUI

/// The felt. Every frame comes from BoardLayout; every gesture goes to GameModel.
struct BoardView: View {
    @ObservedObject var model: GameModel

    static let felt: Color = Color(red: 0.0, green: 0.498, blue: 0.055) // #007F0E

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let layout: BoardLayout = BoardLayout(boardSize: BoardSize(geo.size))
            let state: GameState = model.game.state

            ZStack(alignment: Alignment.topLeading) {
                FeltBackground()

                ForEach(0..<GameState.columnCount, id: \.self) { (column: Int) in
                    EmptySlotView(size: layout.cardSize.cgSize)
                        .position(layout.slotFrame(column: column).cgCenter)
                }

                EmptySlotView(size: layout.foundationAreaFrame.cgSize, dashed: true)
                    .position(layout.foundationAreaFrame.cgCenter)

                ForEach(Array(layout.foundationFrames(count: state.completed.count).enumerated()), id: \.offset) {
                    (item: (offset: Int, element: BoardRect)) in
                    CardView(card: Card(id: -1 - item.offset, suit: state.completed[item.offset], rank: Rank.king, isFaceUp: true),
                             size: item.element.cgSize)
                        .position(item.element.cgCenter)
                }

                ScoreBoxView(score: state.score, moves: state.moves, frame: layout.scoreBoxFrame)

                ForEach(layout.placements(for: state, drag: model.pointer.drag)) { (placement: CardPlacement) in
                    CardView(card: placement.card, size: placement.frame.cgSize)
                        .shadow(color: Color.black.opacity(placement.isLifted ? 0.45 : 0.0),
                                radius: placement.isLifted ? 4 : 0, x: 2, y: 3)
                        .position(placement.frame.cgCenter)
                        .zIndex(placement.zIndex)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            // `.local` is the ZStack's own space, the same one `.position` uses for every card.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: CoordinateSpace.local)
                    .onChanged { (value: DragGesture.Value) in
                        model.pointerChanged(start: value.startLocation, translation: value.translation, layout: layout)
                    }
                    .onEnded { (value: DragGesture.Value) in
                        model.pointerEnded(start: value.startLocation, translation: value.translation, layout: layout)
                    }
            )
        }
        .alert("Spider Solitaire", isPresented: alertBinding) {
            Button("OK", role: ButtonRole.cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .alert("Congratulations, you won!", isPresented: $model.showWinAlert) {
            Button("New Game") { model.newGame(model.game.state.difficulty) }
            Button("Not Now", role: ButtonRole.cancel) {}
        } message: {
            Text("Score: \(model.game.state.score)")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { model.alertMessage != nil },
            set: { (shown: Bool) in if !shown { model.alertMessage = nil } }
        )
    }
}

struct FeltBackground: View {
    var body: some View {
        ZStack {
            BoardView.felt
            RadialGradient(
                gradient: Gradient(colors: [Color.white.opacity(0.06), Color.black.opacity(0.18)]),
                center: UnitPoint.center, startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

struct EmptySlotView: View {
    let size: CGSize
    var dashed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: max(3, size.width * 0.06))
            .stroke(Color.black.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
            .frame(width: size.width, height: size.height)
    }
}

/// XP's dark-green "Score / Moves" box at the bottom centre.
struct ScoreBoxView: View {
    let score: Int
    let moves: Int
    let frame: BoardRect

    var body: some View {
        let fontSize: CGFloat = CGFloat(max(10, min(18, frame.height * 0.24)))
        VStack(spacing: CGFloat(frame.height * 0.08)) {
            Text("Score: \(score)")
            Text("Moves: \(moves)")
        }
        .font(Font.system(size: fontSize, weight: Font.Weight.semibold))
        .foregroundColor(Color.white)
        .frame(width: CGFloat(frame.width), height: CGFloat(frame.height))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.0, green: 0.32, blue: 0.0))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.6), lineWidth: 1))
        )
        .position(frame.cgCenter)
    }
}
#endif
