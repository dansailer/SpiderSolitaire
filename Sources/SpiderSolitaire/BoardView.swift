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
            let highlightedIDs: Set<Int> = model.highlight?.cardIDs(in: state) ?? Set<Int>()
            let highlightedSlot: Int? = model.highlight?.highlightedSlot(in: state)

            ZStack(alignment: Alignment.topLeading) {
                FeltBackground()

                ForEach(0..<GameState.columnCount, id: \.self) { (column: Int) in
                    EmptySlotView(size: layout.cardSize.cgSize, highlighted: highlightedSlot == column)
                        .position(layout.slotFrame(column: column).cgCenter)
                }

                EmptySlotView(size: layout.foundationAreaFrame.cgSize, dashed: true)
                    .position(layout.foundationAreaFrame.cgCenter)

                // During the win animation its Canvas draws the piles as they empty.
                if model.celebration == nil {
                    ForEach(layout.foundationPlacements(for: state, animations: model.animations)) {
                        (placement: CardPlacement) in
                        CardView(card: placement.card, size: placement.frame.cgSize)
                            .position(placement.frame.cgCenter)
                            .zIndex(placement.zIndex)
                    }
                }

                ScoreBoxView(
                    score: state.score, moves: state.moves, seconds: model.elapsedSeconds, frame: layout.scoreBoxFrame
                )
                // Out of the way of the bouncing cards while the win animation runs.
                .opacity(model.celebration == nil ? 1 : 0)
                .animation(Animation.easeInOut(duration: 0.4), value: model.celebration == nil)

                ForEach(
                    layout.placements(
                        for: state, drag: model.pointer.drag, animations: model.animations,
                        highlightedIDs: highlightedIDs)
                ) { (placement: CardPlacement) in
                    CardView(card: placement.card, size: placement.frame.cgSize, isHighlighted: placement.isHighlighted)
                        .shadow(
                            color: Color.black.opacity(placement.isLifted ? 0.45 : 0.0),
                            radius: placement.isLifted ? 4 : 0, x: 2, y: 3
                        )
                        .position(placement.frame.cgCenter)
                        .zIndex(placement.zIndex)
                }

                if let celebration = model.celebration {
                    WinCelebrationView(celebration: celebration, layout: layout)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .zIndex(10_000)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.cardFaceStyle, model.options.cardFaces)
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
            // Overlays sit outside the board's gesture, so they take their own clicks.
            .overlay {
                if model.dealingDifficulty != nil {
                    DealingOverlay(onCancel: { model.cancelWinnableDeal() })
                }
            }
            .overlay {
                if let summary: WinSummary = model.winSummary {
                    WinSummaryOverlay(
                        summary: summary, onPlayAgain: { model.playAgain() }, onClose: { model.closeWinSummary() })
                }
            }
            .overlay(alignment: Alignment.top) {
                if let toast: Achievement = model.toast {
                    AchievementToastView(achievement: toast)
                        .padding(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                        .onTapGesture { model.dismissToast() }
                        .transition(AnyTransition.move(edge: Edge.top).combined(with: AnyTransition.opacity))
                }
            }
        }
        .alert(Text(model.alert?.title ?? "Spider Solitaire"), isPresented: alertBinding, presenting: model.alert) {
            (current: BoardAlert) in
            alertButtons(current)
        } message: { (current: BoardAlert) in
            Text(current.message)
        }
        .sheet(isPresented: $model.showStatisticsSheet) {
            StatisticsSheet(model: model)
        }
    }

    @ViewBuilder
    private func alertButtons(_ current: BoardAlert) -> some View {
        switch current {
        case .info:
            Button(loc("OK"), role: ButtonRole.cancel) {}
        case .noMoves:
            if model.canUndo {
                Button(loc("Undo")) { model.undo() }
            }
            Button(loc("New Game")) { model.requestNewGameFromAlert() }
            Button(loc("OK"), role: ButtonRole.cancel) {}
        case .confirmAbandon(let reason):
            Button(loc("Yes")) { model.confirmAbandon(reason) }
            Button(loc("No"), role: ButtonRole.cancel) {}
        case .openSavedGame:
            Button(loc("Yes")) { model.answerOpenSavedGame(true) }
            Button(loc("No")) { model.answerOpenSavedGame(false) }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { model.alert != nil },
            set: { (shown: Bool) in if !shown { model.alert = nil } }
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
    /// Hint target is this empty column: light it up (XP inverts the slot).
    var highlighted: Bool = false

    var body: some View {
        let radius: CGFloat = max(3, size.width * 0.06)
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.white.opacity(highlighted ? 0.55 : 0.0))
            RoundedRectangle(cornerRadius: radius)
                .stroke(
                    Color.black.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// XP's dark-green "Score / Moves" box at the bottom centre.
struct ScoreBoxView: View {
    let score: Int
    let moves: Int
    let seconds: Int
    let frame: BoardRect

    var body: some View {
        let fontSize: CGFloat = CGFloat(max(9, min(16, frame.height * 0.2)))
        VStack(spacing: CGFloat(frame.height * 0.04)) {
            Text(loc("Score: %lld", score))
            Text(loc("Moves: %lld", moves))
            Text(loc("Time: %@", PlayClock.text(seconds)))
                .monospacedDigit()
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
