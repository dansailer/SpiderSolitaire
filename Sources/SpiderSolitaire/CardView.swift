#if canImport(SwiftUI)
import SpiderBoard
import SpiderCore
import SwiftUI

/// A code-drawn card (no bitmap assets). Size-independent: everything scales with `size.width`.
struct CardView: View {
    let card: Card
    let size: CGSize
    /// Hint flash: XP shows the card with inverted colours.
    var isHighlighted: Bool = false

    var body: some View {
        if isHighlighted {
            content.colorInvert()
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            if card.isFaceUp {
                CardFaceView(card: card, size: size)
            } else {
                CardBackView(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private extension Suit {
    var color: Color { isRed ? Color(red: 0.80, green: 0.0, blue: 0.0) : Color.black }
}

struct CardFaceView: View {
    let card: Card
    let size: CGSize

    private var corner: CGFloat { max(3, size.width * 0.07) }

    var body: some View {
        ZStack(alignment: Alignment.topLeading) {
            RoundedRectangle(cornerRadius: corner)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: corner)
                .stroke(Color.black.opacity(0.75), lineWidth: 1)

            centre

            cornerIndex
                .position(x: size.width * 0.13, y: size.height * 0.15)
            cornerIndex
                .rotationEffect(Angle.degrees(180))
                .position(x: size.width * 0.87, y: size.height * 0.85)
        }
        .frame(width: size.width, height: size.height)
    }

    private var cornerIndex: some View {
        VStack(spacing: 0) {
            Text(card.rank.label)
                .font(Font.system(size: size.width * 0.19, weight: Font.Weight.bold, design: Font.Design.serif))
            Text(card.suit.symbol)
                .font(Font.system(size: size.width * 0.16))
        }
        .foregroundColor(card.suit.color)
        .fixedSize()
    }

    @ViewBuilder
    private var centre: some View {
        if CardFace.isCourt(card.rank) {
            courtCentre
        } else if card.rank == Rank.ace {
            Text(card.suit.symbol)
                .font(Font.system(size: size.width * 0.5))
                .foregroundColor(card.suit.color)
                .position(x: size.width / 2, y: size.height / 2)
        } else {
            ForEach(Array(CardFace.pips(for: card.rank).enumerated()), id: \.offset) { (item: (offset: Int, element: Pip)) in
                Text(card.suit.symbol)
                    .font(Font.system(size: size.width * 0.21))
                    .foregroundColor(card.suit.color)
                    .rotationEffect(Angle.degrees(item.element.inverted ? 180 : 0))
                    .position(pipPoint(item.element))
            }
        }
    }

    private var courtCentre: some View {
        let inset: CGRect = CGRect(x: size.width * 0.24, y: size.height * 0.16,
                                   width: size.width * 0.52, height: size.height * 0.68)
        return ZStack {
            Rectangle()
                .fill(card.suit.color.opacity(0.08))
            Rectangle()
                .stroke(card.suit.color.opacity(0.7), lineWidth: 1)
            VStack(spacing: size.height * 0.02) {
                Text(card.rank.label)
                    .font(Font.system(size: size.width * 0.3, weight: Font.Weight.bold, design: Font.Design.serif))
                Text(card.suit.symbol)
                    .font(Font.system(size: size.width * 0.22))
            }
            .foregroundColor(card.suit.color)
        }
        .frame(width: inset.width, height: inset.height)
        .position(x: inset.midX, y: inset.midY)
    }

    private func pipPoint(_ pip: Pip) -> CGPoint {
        let a = CardFace.pipArea
        let x: Double = a.minX + (a.maxX - a.minX) * pip.x
        let y: Double = a.minY + (a.maxY - a.minY) * pip.y
        return CGPoint(x: size.width * CGFloat(x), y: size.height * CGFloat(y))
    }
}

/// XP-ish blue back: white rim, blue field, light lattice pattern.
struct CardBackView: View {
    let size: CGSize

    private var corner: CGFloat { max(3, size.width * 0.07) }

    var body: some View {
        let rim: CGFloat = max(2, size.width * 0.06)
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: max(2, corner - rim / 2))
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.16, green: 0.33, blue: 0.80),
                                                Color(red: 0.05, green: 0.16, blue: 0.55)]),
                    startPoint: UnitPoint.topLeading, endPoint: UnitPoint.bottomTrailing))
                .overlay(
                    LatticeShape(spacing: max(4, size.width * 0.11))
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: max(2, corner - rim / 2)))
                .padding(rim)
            RoundedRectangle(cornerRadius: corner)
                .stroke(Color.black.opacity(0.75), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Diagonal criss-cross lines filling the rect.
struct LatticeShape: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var offset: CGFloat = -rect.height
        while offset < rect.width + rect.height {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            offset += spacing
        }
        return path
    }
}
#endif
