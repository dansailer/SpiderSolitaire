#if canImport(SwiftUI)
import SpiderBoard
import SpiderCore
import SwiftUI

/// Draws `WinCelebration` every display frame: bouncing completed-suit cards with trails plus
/// firework sparks. Tapping anywhere skips to the "Congratulations" dialog.
struct WinCelebrationView: View {
    let celebration: GameModel.Celebration
    let layout: BoardLayout
    let onSkip: () -> Void

    static let palette: [Color] = [
        Color(red: 1.0, green: 0.85, blue: 0.2),
        Color(red: 1.0, green: 0.35, blue: 0.3),
        Color(red: 0.4, green: 0.8, blue: 1.0),
        Color(red: 0.75, green: 0.5, blue: 1.0),
        Color(red: 0.5, green: 1.0, blue: 0.5),
        Color.white,
    ]

    var body: some View {
        let simulation: WinCelebration = WinCelebration(layout: layout, suits: celebration.suits, seed: celebration.seed)
        let cardSize: CGSize = layout.cardSize.cgSize
        TimelineView(AnimationTimelineSchedule()) { context in
            let t: Double = context.date.timeIntervalSince(celebration.start)
            Canvas { (graphics: inout GraphicsContext, size: CGSize) in
                for sprite in simulation.sprites(at: t) {
                    let centre: CGPoint = CGPoint(x: CGFloat(sprite.center.x), y: CGFloat(sprite.center.y))
                    switch sprite.kind {
                    case .card(let id):
                        guard let symbol: GraphicsContext.ResolvedSymbol = graphics.resolveSymbol(id: id) else { continue }
                        var layer: GraphicsContext = graphics
                        layer.opacity = sprite.alpha
                        layer.draw(symbol, at: centre, anchor: UnitPoint.center)
                    case .spark(let colorIndex):
                        let r: CGFloat = CGFloat(sprite.radius)
                        let colour: Color = WinCelebrationView.palette[colorIndex % WinCelebrationView.palette.count]
                        graphics.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                                      with: GraphicsContext.Shading.color(colour.opacity(sprite.alpha)))
                    }
                }
            } symbols: {
                ForEach(simulation.cards) { (card: Card) in
                    CardView(card: card, size: cardSize)
                        .tag(card.id)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSkip() }
        .allowsHitTesting(true)
    }
}
#endif
