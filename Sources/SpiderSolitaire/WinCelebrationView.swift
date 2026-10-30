#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore
import SwiftUI

/// Draws `WinCelebration` every display frame: the painted card trails, firework sparks behind the
/// cards, the foundation piles as they empty and the cards in flight. Once the show has stopped
/// (`stoppedAt`) the timeline pauses and the last frame fades out under the win panel. Clicks go
/// to the board's gesture, which skips to the panel.
struct WinCelebrationView: View {
    let celebration: GameModel.Celebration
    let layout: BoardLayout
    @Environment(\.cardFaceStyle) private var faceStyle: CardFaceStyle
    @Environment(\.displayScale) private var displayScale: CGFloat
    @State private var trails: CelebrationTrails = CelebrationTrails()

    static let palette: [Color] = [
        Color(red: 1.0, green: 0.85, blue: 0.2),
        Color(red: 1.0, green: 0.35, blue: 0.3),
        Color(red: 0.4, green: 0.8, blue: 1.0),
        Color(red: 0.75, green: 0.5, blue: 1.0),
        Color(red: 0.5, green: 1.0, blue: 0.5),
        Color.white,
    ]

    var body: some View {
        let show: WinCelebration = celebration.show
        let cardSize: CGSize = layout.cardSize.cgSize
        let running: Bool = celebration.stoppedAt == nil
        TimelineView(AnimationTimelineSchedule(minimumInterval: 1.0 / 60, paused: !running)) {
            (context: TimelineViewDefaultContext) in
            let t: Double = celebration.stoppedAt ?? context.date.timeIntervalSince(celebration.start)
            let trail: CelebrationTrails.Frame? = trails.advance(
                to: t, show: show, layout: layout, faceStyle: faceStyle, displayScale: displayScale)
            Canvas { (graphics: inout GraphicsContext, _: CGSize) in
                if let trail {
                    graphics.draw(
                        Image(decorative: trail.image, scale: trail.scale),
                        in: CGRect(origin: CGPoint.zero, size: layout.boardSize.cgSize))
                }
                if running {
                    for spark in show.sparks(at: t, layout: layout) {
                        let r: CGFloat = CGFloat(spark.radius)
                        let centre: CGPoint = CGPoint(x: CGFloat(spark.center.x), y: CGFloat(spark.center.y))
                        let colour: Color = WinCelebrationView.palette[
                            spark.colorIndex % WinCelebrationView.palette.count]
                        graphics.fill(
                            Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                            with: GraphicsContext.Shading.color(colour.opacity(spark.alpha)))
                    }
                }
                let slots: [BoardRect] = layout.foundationFrames(count: show.suits.count)
                for top in show.pileTops(at: t) where slots.indices.contains(top.pile) {
                    WinCelebrationView.draw(top.card, at: slots[top.pile].cgCenter, in: graphics)
                }
                for flying in show.cardsInFlight(at: t, layout: layout) {
                    let centre: CGPoint = CGPoint(x: CGFloat(flying.center.x), y: CGFloat(flying.center.y))
                    WinCelebrationView.draw(flying.card, at: centre, in: graphics)
                }
            } symbols: {
                ForEach(show.cards) { (card: Card) in
                    CardView(card: card, size: cardSize)
                        .tag(card.id)
                }
            }
        }
        // Once stopped, the trails and any card still in the air fade away under the win panel.
        .opacity(running ? 1 : 0)
        .animation(Animation.easeOut(duration: WinPanelTiming.afterShow), value: running)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ card: Card, at centre: CGPoint, in graphics: GraphicsContext) {
        guard let symbol: GraphicsContext.ResolvedSymbol = graphics.resolveSymbol(id: card.id) else { return }
        graphics.draw(symbol, at: centre, anchor: UnitPoint.center)
    }
}

/// The win animation's trail layer: one bitmap the size of the board into which every card in the
/// air is stamped each `WinCelebration.trailStep` of show time (classic Windows style), fading by
/// half every `trailHalfLife` seconds. Only the new stamps are drawn each frame, never the old
/// copies. The bitmap is capped at `maxPixels` (it drops below the display's scale on large
/// Retina windows; the cards in flight stay sharp). A new board size starts a clear layer.
@MainActor
final class CelebrationTrails {
    struct Frame {
        let image: CGImage
        let scale: CGFloat
    }

    static let maxPixels: Double = 2_500_000
    /// After a stall, at most this many steps are stamped at once.
    static let maxCatchUpSteps: Int = 30

    private var context: CGContext?
    private var boardSize: BoardSize?
    private var faceStyle: CardFaceStyle?
    private var scale: CGFloat = 1
    private var stampedStep: Int = -1
    private var stamps: [String: CGImage] = [:]
    private var frame: Frame?

    private var fadeEvery: Int {
        max(1, Int((WinCelebration.trailFadeInterval / WinCelebration.trailStep).rounded()))
    }

    func advance(
        to t: Double, show: WinCelebration, layout: BoardLayout, faceStyle: CardFaceStyle, displayScale: CGFloat
    ) -> Frame? {
        let target: Int = Int((max(0, t) / WinCelebration.trailStep).rounded(FloatingPointRoundingRule.down))
        if context == nil || boardSize != layout.boardSize || self.faceStyle != faceStyle {
            start(layout: layout, faceStyle: faceStyle, displayScale: displayScale)
            // Continue from now: a resized board starts clear rather than replaying the past.
            stampedStep = target - 1
        }
        guard let context, target > stampedStep else { return frame }

        let fade: CGFloat = CGFloat(
            1 - pow(0.5, WinCelebration.trailFadeInterval / WinCelebration.trailHalfLife))
        let height: Double = layout.boardSize.height
        let cardSize: CGSize = layout.cardSize.cgSize
        for step in max(stampedStep + 1, target - CelebrationTrails.maxCatchUpSteps)...target {
            if step > 0, step.isMultiple(of: fadeEvery) {
                context.setBlendMode(CGBlendMode.destinationOut)
                context.setFillColor(CGColor(gray: 0, alpha: fade))
                context.fill(CGRect(x: 0, y: 0, width: layout.boardSize.width, height: height))
                context.setBlendMode(CGBlendMode.normal)
            }
            let time: Double = Double(step) * WinCelebration.trailStep
            for flying in show.cardsInFlight(at: time, layout: layout) {
                guard let stamp: CGImage = stamp(flying.card, size: cardSize, faceStyle: faceStyle) else { continue }
                // CoreGraphics y runs up; drawing unflipped keeps the card upright.
                let rect: CGRect = CGRect(
                    x: flying.center.x - cardSize.width / 2, y: height - flying.center.y - cardSize.height / 2,
                    width: cardSize.width, height: cardSize.height)
                context.draw(stamp, in: rect)
            }
        }
        stampedStep = target
        if let image: CGImage = context.makeImage() {
            frame = Frame(image: image, scale: scale)
        }
        return frame
    }

    private func start(layout: BoardLayout, faceStyle: CardFaceStyle, displayScale: CGFloat) {
        let w: Double = max(1, layout.boardSize.width)
        let h: Double = max(1, layout.boardSize.height)
        let cap: Double = (CelebrationTrails.maxPixels / (w * h)).squareRoot()
        scale = CGFloat(max(0.5, min(Double(displayScale), cap)))
        boardSize = layout.boardSize
        self.faceStyle = faceStyle
        stamps = [:]
        frame = nil
        context = CGContext(
            data: nil, width: Int((w * Double(scale)).rounded(FloatingPointRoundingRule.up)),
            height: Int((h * Double(scale)).rounded(FloatingPointRoundingRule.up)), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.scaleBy(x: scale, y: scale)
        context?.interpolationQuality = CGInterpolationQuality.none
    }

    /// The card's face at the layer's scale, rendered once per card (Classic faces come from the
    /// card bitmap cache through CardView).
    private func stamp(_ card: Card, size: CGSize, faceStyle: CardFaceStyle) -> CGImage? {
        let key: String = "\(card.suit.rawValue)-\(card.rank.rawValue)"
        if let cached: CGImage = stamps[key] { return cached }
        let face: Card = Card(id: 0, suit: card.suit, rank: card.rank, isFaceUp: true)
        let renderer: ImageRenderer<some View> = ImageRenderer(
            content: CardView(card: face, size: size)
                .environment(\.cardFaceStyle, faceStyle)
                .environment(\.displayScale, scale))
        renderer.scale = scale
        guard let image: CGImage = renderer.cgImage else { return nil }
        stamps[key] = image
        return image
    }
}
#endif
