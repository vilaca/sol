import SolitaireCore
import SwiftUI

struct CardView: View {
    let card: Card
    let size: CGSize
    /// What VoiceOver says; defaults to the card's name.
    var accessibilityText: String?
    /// Outlined by the hint button.
    var isHinted = false

    private var w: CGFloat { size.width }
    private var radius: CGFloat { w * 0.12 }
    private var ink: Color {
        card.suit.isRed ? Color(red: 0.8, green: 0.11, blue: 0.2) : Color(red: 0.11, green: 0.12, blue: 0.16)
    }

    var body: some View {
        ZStack {
            if card.isFaceUp { face } else { back }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
        .modifier(HintGlow(isOn: isHinted, size: size))
        .accessibilityElement()
        .accessibilityLabel(accessibilityText ?? (card.isFaceUp ? card.spokenName : String(localized: "Face-down card")))
    }

    // MARK: - Face

    private var face: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 1, green: 0.995, blue: 0.98), Color(red: 0.95, green: 0.94, blue: 0.91)],
                startPoint: .top,
                endPoint: .bottom
            )
            // Index row: stays readable when the card is covered in a column.
            HStack(alignment: .center, spacing: 0) {
                Text(card.rankLabel)
                    .font(.system(size: w * 0.3, weight: .bold, design: .rounded))
                    .tracking(card.rank == 10 ? -w * 0.03 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                suitImage(size: w * 0.23)
            }
            .padding(.horizontal, w * 0.09)
            .padding(.top, w * 0.04)

            centre
                .padding(.top, size.height * 0.31)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundColor(ink)
    }

    @ViewBuilder private var centre: some View {
        switch card.rank {
        case 11...13:
            courtPanel
                .padding(.horizontal, w * 0.09)
                .padding(.bottom, w * 0.07)
        case 1:
            suitImage(size: w * 0.62)
                .padding(.bottom, w * 0.08)
        default:
            suitImage(size: w * 0.5)
                .padding(.bottom, w * 0.1)
        }
    }

    private static let courtFrame = Color(red: 0.33, green: 0.33, blue: 0.65)

    /// J, Q, K: the classic English-pattern figure (see Art/court/README.md), framed under the index.
    private var courtPanel: some View {
        let shape = RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
        return Image("court-\(card.rankLabel)\(card.suit.letter)")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Self.courtFrame, lineWidth: max(0.75, w * 0.015)))
    }

    private func suitImage(size: CGFloat) -> some View {
        Image(systemName: card.suit.systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    // MARK: - Back

    private var back: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.33, blue: 0.6), Color(red: 0.06, green: 0.15, blue: 0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            BackPattern()
                .stroke(Color.white.opacity(0.13), lineWidth: max(0.5, w * 0.012))
                .clipped()
                .padding(w * 0.1)
            RoundedRectangle(cornerRadius: radius * 0.55, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: max(1, w * 0.025))
                .padding(w * 0.07)
            Circle()
                .fill(Color(red: 0.07, green: 0.17, blue: 0.4))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: max(0.75, w * 0.02)))
                .frame(width: w * 0.42, height: w * 0.42)
            Image(systemName: "sun.max.fill")
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.26, height: w * 0.26)
                .foregroundColor(Color(red: 1, green: 0.8, blue: 0.35))
        }
    }
}

/// Diagonal lattice for the card back.
private struct BackPattern: Shape {
    func path(in rect: CGRect) -> Path {
        // 45° lines, cut to the rect so the shape (and the card's tap area) never extends past the card.
        var path = Path()
        let step = rect.width / 4
        let w = rect.width, h = rect.height
        func segment(_ from: CGPoint, _ to: CGPoint) {
            path.move(to: CGPoint(x: rect.minX + from.x, y: rect.minY + from.y))
            path.addLine(to: CGPoint(x: rect.minX + to.x, y: rect.minY + to.y))
        }
        var offset = -h
        while offset < w {
            // Down-right line x = offset + y.
            let a = max(0, -offset), b = min(h, w - offset)
            if a < b { segment(CGPoint(x: offset + a, y: a), CGPoint(x: offset + b, y: b)) }
            // Down-left line x = offset + h - y.
            let c = max(0, offset + h - w), d = min(h, offset + h)
            if c < d { segment(CGPoint(x: offset + h - c, y: c), CGPoint(x: offset + h - d, y: d)) }
            offset += step
        }
        return path
    }
}

private extension Suit {
    var letter: String {
        switch self {
        case .spades: "S"
        case .hearts: "H"
        case .diamonds: "D"
        case .clubs: "C"
        }
    }

    var systemImage: String {
        switch self {
        case .spades: "suit.spade.fill"
        case .hearts: "suit.heart.fill"
        case .diamonds: "suit.diamond.fill"
        case .clubs: "suit.club.fill"
        }
    }
}

/// Outline marking an empty pile.
struct SlotView: View {
    let size: CGSize
    var symbol: String?
    var text: String?

    var body: some View {
        RoundedRectangle(cornerRadius: size.width * 0.1)
            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: size.width * 0.1).fill(Color.black.opacity(0.08)))
            .overlay(label.foregroundColor(Color.white.opacity(0.35)))
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var label: some View {
        if let symbol {
            Image(systemName: symbol).font(.system(size: size.width * 0.35, weight: .semibold))
        } else if let text {
            Text(text).font(.system(size: size.width * 0.35, weight: .semibold, design: .rounded))
        }
    }
}

/// The yellow outline the hint draws around a card or an empty pile.
struct HintGlow: ViewModifier {
    let isOn: Bool
    let size: CGSize

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: size.width * 0.12, style: .continuous)
                .strokeBorder(Color(red: 1, green: 0.84, blue: 0.2), lineWidth: max(2, size.width * 0.06))
                .shadow(color: Color(red: 1, green: 0.84, blue: 0.2).opacity(0.8), radius: 6)
                .opacity(isOn ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}
