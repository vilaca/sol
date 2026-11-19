import CoreGraphics
import SolitaireCore

struct PlacedCard: Identifiable {
    let card: Card
    let pile: Pile
    let index: Int
    let center: CGPoint
    let zIndex: Double

    var id: Int { card.id }
}

/// Where every slot and card sits for a given board size. Pure geometry, no views.
struct BoardLayout {
    let size: CGSize
    let spacing: CGFloat
    let cardSize: CGSize
    /// Left edge of the first column; centres the seven columns on wide screens.
    let inset: CGFloat

    private static let aspect: CGFloat = 1.4
    private static let columns = 7

    init(size: CGSize) {
        self.size = size
        let spacing = max(4, min(size.width, size.height) * 0.015)
        let byWidth = (size.width - spacing * CGFloat(Self.columns + 1)) / CGFloat(Self.columns)
        // Leave room for the top row plus a tableau about 4.5 cards tall, so that on wide screens
        // (iPad in landscape) a long column keeps the corner indexes readable instead of squeezing.
        let byHeight = (size.height - spacing * 4) / (Self.aspect * 5.5)
        let width = max(10, min(byWidth, byHeight))
        self.spacing = spacing
        cardSize = CGSize(width: width, height: width * Self.aspect)
        inset = (size.width - (CGFloat(Self.columns) * width + CGFloat(Self.columns - 1) * spacing)) / 2
    }

    var topRowY: CGFloat { spacing + cardSize.height / 2 }
    var tableauTop: CGFloat { spacing * 3 + cardSize.height }

    func x(column: Int) -> CGFloat {
        inset + CGFloat(column) * (cardSize.width + spacing) + cardSize.width / 2
    }

    func slotCenter(_ pile: Pile) -> CGPoint {
        switch pile {
        case .stock: CGPoint(x: x(column: 0), y: topRowY)
        case .waste: CGPoint(x: x(column: 1), y: topRowY)
        case .foundation(let i): CGPoint(x: x(column: 3 + i), y: topRowY)
        case .tableau(let i): CGPoint(x: x(column: i), y: tableauTop + cardSize.height / 2)
        }
    }

    /// The pile a card dropped with its centre at `point` lands on.
    func pile(at point: CGPoint) -> Pile? {
        let column = Int(((point.x - inset + spacing / 2) / (cardSize.width + spacing)).rounded(.down))
        guard (0..<Self.columns).contains(column) else { return nil }
        if point.y < tableauTop - spacing {
            return column >= 3 ? .foundation(column - 3) : nil
        }
        return .tableau(column)
    }

    func place(_ game: Klondike, raised: Set<Int>) -> [PlacedCard] {
        var result: [PlacedCard] = []
        result.reserveCapacity(52)

        func add(_ card: Card, _ pile: Pile, _ index: Int, _ center: CGPoint) {
            let z = Double(index) + (raised.contains(card.id) ? 100 : 0)
            result.append(PlacedCard(card: card, pile: pile, index: index, center: center, zIndex: z))
        }

        for (i, card) in game.stock.enumerated() {
            add(card, .stock, i, slotCenter(.stock))
        }

        let fan = cardSize.width * 0.28
        let fanned = min(game.drawCount, game.waste.count)
        for (i, card) in game.waste.enumerated() {
            var center = slotCenter(.waste)
            center.x += CGFloat(max(0, i - (game.waste.count - fanned))) * fan
            add(card, .waste, i, center)
        }

        for (f, pile) in game.foundations.enumerated() {
            for (i, card) in pile.enumerated() {
                add(card, .foundation(f), i, slotCenter(.foundation(f)))
            }
        }

        for (t, column) in game.tableau.enumerated() {
            let offsets = tableauOffsets(column)
            for (i, card) in column.enumerated() {
                var center = slotCenter(.tableau(t))
                center.y += offsets[i]
                add(card, .tableau(t), i, center)
            }
        }
        return result
    }

    /// Vertical offset of each card in a column, squeezed when the column would run off the screen.
    private func tableauOffsets(_ column: [Card]) -> [CGFloat] {
        let steps = column.dropLast().map { $0.isFaceUp ? cardSize.height * 0.31 : cardSize.height * 0.12 }
        let total = steps.reduce(0, +)
        let available = max(0, size.height - tableauTop - cardSize.height - spacing)
        let scale = total > available ? available / total : 1
        var offsets: [CGFloat] = []
        var y: CGFloat = 0
        for i in column.indices {
            offsets.append(y)
            if i < steps.count { y += steps[i] * scale }
        }
        return offsets
    }
}
