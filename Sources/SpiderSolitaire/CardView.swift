#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore
import SwiftUI

/// Options → Card faces, handed down from BoardView so every CardView (including the win
/// celebration's Canvas symbols) draws the same set.
private struct CardFaceStyleKey: EnvironmentKey {
    static let defaultValue: CardFaceStyle = CardFaceStyle.classic
}

extension EnvironmentValues {
    var cardFaceStyle: CardFaceStyle {
        get { self[CardFaceStyleKey.self] }
        set { self[CardFaceStyleKey.self] = newValue }
    }
}

/// One card. Face-up cards use the Classic art when it is selected and its image exists,
/// otherwise the code-drawn face. Size-independent: everything scales with `size.width`.
struct CardView: View {
    let card: Card
    let size: CGSize
    /// Hint flash: XP shows the card with inverted colours; we add a bright outline too.
    var isHighlighted: Bool = false
    @Environment(\.cardFaceStyle) private var faceStyle: CardFaceStyle

    var body: some View {
        if isHighlighted {
            content
                .colorInvert()
                .overlay(
                    RoundedRectangle(cornerRadius: CardStyle.cornerRadius(size))
                        .strokeBorder(CardStyle.highlight, lineWidth: max(2, size.width * 0.035))
                )
                .shadow(color: CardStyle.highlight.opacity(0.8), radius: 5, x: 0, y: 0)
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            if card.isFaceUp {
                if faceStyle == CardFaceStyle.classic, let image: NSImage = ClassicCardImages.shared.image(for: card) {
                    ClassicCardFaceView(image: image, size: size)
                } else {
                    CardFaceView(card: card, size: size)
                }
            } else {
                CardBackView(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Shared colours and metrics, close to the Windows XP card set.
enum CardStyle {
    static let red: Color = Color(red: 0.85, green: 0.0, blue: 0.0)
    static let black: Color = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let border: Color = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let gold: Color = Color(red: 0.96, green: 0.78, blue: 0.20)
    static let courtBlue: Color = Color(red: 0.16, green: 0.30, blue: 0.72)
    static let highlight: Color = Color(red: 1.0, green: 0.85, blue: 0.1)

    static func cornerRadius(_ size: CGSize) -> CGFloat { max(3, size.width * 0.07) }

    static func color(_ suit: Suit) -> Color { suit.isRed ? red : black }
}

/// Classic face: the bitmap (transparent outside the art), fitted without distortion onto the white card, clipped to the
/// card's rounded rect, with the same 1 pt border as the simple face.
struct ClassicCardFaceView: View {
    let image: NSImage
    let size: CGSize

    var body: some View {
        let radius: CGFloat = CardStyle.cornerRadius(size)
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.white)
            // The art keeps its own 2:3 proportions (one uniform scale), centred on the 71:96 card.
            Image(nsImage: image)
                .resizable()
                .interpolation(Image.Interpolation.high)
                .antialiased(true)
                .aspectRatio(contentMode: ContentMode.fit)
                .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(CardStyle.border, lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct CardFaceView: View {
    let card: Card
    let size: CGSize

    var body: some View {
        let radius: CGFloat = CardStyle.cornerRadius(size)
        ZStack(alignment: Alignment.topLeading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(CardStyle.border, lineWidth: 1)

            centre

            cornerIndex
                .position(x: size.width * 0.12, y: size.height * 0.14)
            cornerIndex
                .rotationEffect(Angle.degrees(180))
                .position(x: size.width * 0.88, y: size.height * 0.86)
        }
        .frame(width: size.width, height: size.height)
    }

    private var cornerIndex: some View {
        VStack(spacing: -size.width * 0.02) {
            Text(card.rank.label)
                .font(Font.system(size: size.width * (card.rank == Rank.ten ? 0.17 : 0.2),
                                  weight: Font.Weight.bold, design: Font.Design.default))
                .kerning(card.rank == Rank.ten ? -1 : 0)
            Text(card.suit.symbol)
                .font(Font.system(size: size.width * 0.17))
        }
        .foregroundColor(CardStyle.color(card.suit))
        .fixedSize()
    }

    @ViewBuilder
    private var centre: some View {
        if CardFace.isCourt(card.rank) {
            CourtPanel(card: card, size: size)
                .position(x: size.width / 2, y: size.height / 2)
        } else if card.rank == Rank.ace {
            Text(card.suit.symbol)
                .font(Font.system(size: size.width * (card.suit == Suit.spades ? 0.62 : 0.5)))
                .foregroundColor(CardStyle.color(card.suit))
                .position(x: size.width / 2, y: size.height / 2)
        } else {
            ForEach(Array(CardFace.pips(for: card.rank).enumerated()), id: \.offset) { (item: (offset: Int, element: Pip)) in
                Text(card.suit.symbol)
                    .font(Font.system(size: size.width * 0.22))
                    .foregroundColor(CardStyle.color(card.suit))
                    .rotationEffect(Angle.degrees(item.element.inverted ? 180 : 0))
                    .position(pipPoint(item.element))
            }
        }
    }

    private func pipPoint(_ pip: Pip) -> CGPoint {
        let a = CardFace.pipArea
        let x: Double = a.minX + (a.maxX - a.minX) * pip.x
        let y: Double = a.minY + (a.maxY - a.minY) * pip.y
        return CGPoint(x: size.width * CGFloat(x), y: size.height * CGFloat(y))
    }
}

/// Double-headed court panel, XP-flavoured: gold/blue frame, a headpiece (crown, tiara or cap)
/// over a serif monogram, mirrored in the bottom half like a real court card.
struct CourtPanel: View {
    let card: Card
    let size: CGSize

    var body: some View {
        let panel: CGSize = CGSize(width: size.width * 0.56, height: size.height * 0.70)
        let half: CGSize = CGSize(width: panel.width, height: panel.height / 2)
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color.white, CardStyle.gold.opacity(0.25)]),
                    startPoint: UnitPoint.top, endPoint: UnitPoint.bottom))
            VStack(spacing: 0) {
                CourtHalf(card: card, size: half)
                CourtHalf(card: card, size: half)
                    .rotationEffect(Angle.degrees(180))
            }
            Rectangle()
                .fill(CardStyle.color(card.suit).opacity(0.5))
                .frame(width: panel.width * 0.9, height: 1)
            Rectangle()
                .strokeBorder(CardStyle.courtBlue, lineWidth: max(1, size.width * 0.02))
            Rectangle()
                .strokeBorder(CardStyle.gold, lineWidth: max(1, size.width * 0.012))
                .padding(max(1.5, size.width * 0.03))
        }
        .frame(width: panel.width, height: panel.height)
    }
}

struct CourtHalf: View {
    let card: Card
    let size: CGSize

    var body: some View {
        let colour: Color = CardStyle.color(card.suit)
        VStack(spacing: size.height * 0.02) {
            headpiece
                .frame(width: size.width * 0.55, height: size.height * 0.26)
            HStack(alignment: VerticalAlignment.firstTextBaseline, spacing: size.width * 0.03) {
                Text(card.rank.label)
                    .font(Font.system(size: size.height * 0.42, weight: Font.Weight.bold, design: Font.Design.serif))
                Text(card.suit.symbol)
                    .font(Font.system(size: size.height * 0.24))
            }
            .foregroundColor(colour)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var headpiece: some View {
        switch card.rank {
        case .king:
            ZStack {
                CrownShape().fill(CardStyle.gold)
                CrownShape().stroke(CardStyle.color(card.suit), lineWidth: 1)
            }
        case .queen:
            ZStack {
                TiaraShape().fill(CardStyle.gold)
                TiaraShape().stroke(CardStyle.color(card.suit), lineWidth: 1)
            }
        default:
            ZStack {
                CapShape().fill(CardStyle.courtBlue)
                CapShape().stroke(CardStyle.gold, lineWidth: 1)
            }
        }
    }
}

/// Five-point crown on a band.
struct CrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w: CGFloat = rect.width, h: CGFloat = rect.height
        let x: CGFloat = rect.minX, y: CGFloat = rect.minY
        p.move(to: CGPoint(x: x, y: y + h))
        p.addLine(to: CGPoint(x: x, y: y + h * 0.25))
        p.addLine(to: CGPoint(x: x + w * 0.25, y: y + h * 0.6))
        p.addLine(to: CGPoint(x: x + w * 0.5, y: y))
        p.addLine(to: CGPoint(x: x + w * 0.75, y: y + h * 0.6))
        p.addLine(to: CGPoint(x: x + w, y: y + h * 0.25))
        p.addLine(to: CGPoint(x: x + w, y: y + h))
        p.closeSubpath()
        return p
    }
}

/// Rounded tiara with three jewels.
struct TiaraShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w: CGFloat = rect.width, h: CGFloat = rect.height
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - h * 0.4))
        p.closeSubpath()
        let r: CGFloat = min(w, h) * 0.14
        for fx in [0.25, 0.5, 0.75] as [CGFloat] {
            let cy: CGFloat = fx == 0.5 ? rect.minY + r : rect.minY + h * 0.35
            p.addEllipse(in: CGRect(x: rect.minX + w * fx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        return p
    }
}

/// A jack's cap with a feather tip.
struct CapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w: CGFloat = rect.width, h: CGFloat = rect.height
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY))
        p.closeSubpath()
        p.move(to: CGPoint(x: rect.midX + w * 0.1, y: rect.minY + h * 0.45))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + h * 0.4))
        p.addQuadCurve(to: CGPoint(x: rect.midX + w * 0.1, y: rect.minY + h * 0.45), control: CGPoint(x: rect.midX + w * 0.2, y: rect.minY))
        return p
    }
}

/// Blue back: white rim, gradient field, fine lattice, gold frame and a rosette. The artwork is
/// `CardBackArt` (SpiderBoard), the same description the icon tool and Linux previews draw.
struct CardBackView: View {
    let size: CGSize

    var body: some View {
        VectorSceneView(scene: CardBackArt.scene(size: BoardSize(width: Double(size.width), height: Double(size.height))))
            .frame(width: size.width, height: size.height)
    }
}

/// Draws a `VectorScene` with one Canvas. Scene units are points, so no scaling happens here.
struct VectorSceneView: View {
    let scene: VectorScene

    var body: some View {
        let scene: VectorScene = self.scene
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            VectorSceneView.draw(scene, in: &context)
        }
    }

    static func draw(_ scene: VectorScene, in context: inout GraphicsContext) {
        for item in scene.items {
            var layer: GraphicsContext = context
            if let clip: VectorPath = item.clip {
                layer.clip(to: path(clip))
            }
            if let s: SpiderBoard.Shadow = item.shadow {
                layer.addFilter(GraphicsContext.Filter.shadow(color: color(s.color), radius: CGFloat(s.blur / 2),
                                                              x: CGFloat(s.dx), y: CGFloat(s.dy)))
            }
            let shape: Path = path(item.path)
            if let fill: SpiderBoard.Paint = item.fill {
                layer.fill(shape, with: shading(fill))
            }
            if let stroke: SpiderBoard.Stroke = item.stroke {
                layer.stroke(shape, with: GraphicsContext.Shading.color(color(stroke.color)),
                             style: StrokeStyle(lineWidth: CGFloat(stroke.width), lineCap: CGLineCap.round, lineJoin: CGLineJoin.round))
            }
        }
    }

    static func color(_ c: RGBA) -> Color {
        Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    static func point(_ p: BoardPoint) -> CGPoint { CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }

    static func path(_ vector: VectorPath) -> Path {
        var p: Path = Path()
        for command in vector.commands {
            switch command {
            case .move(let to): p.move(to: point(to))
            case .line(let to): p.addLine(to: point(to))
            case .curve(let c1, let c2, let to): p.addCurve(to: point(to), control1: point(c1), control2: point(c2))
            case .close: p.closeSubpath()
            }
        }
        return p
    }

    static func shading(_ paint: SpiderBoard.Paint) -> GraphicsContext.Shading {
        switch paint {
        case .solid(let c):
            return GraphicsContext.Shading.color(color(c))
        case .linear(let start, let end, let from, let to):
            return GraphicsContext.Shading.linearGradient(Gradient(colors: [color(from), color(to)]),
                                                          startPoint: point(start), endPoint: point(end))
        case .radial(let center, let radius, let from, let to):
            return GraphicsContext.Shading.radialGradient(Gradient(colors: [color(from), color(to)]),
                                                          center: point(center), startRadius: 0, endRadius: CGFloat(radius))
        }
    }
}
#endif
