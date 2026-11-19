import CoreGraphics
import SolitaireCore

/// How a pile spreads its cards.
enum Fan: Equatable {
    /// All on one spot (stock, foundations, free cells).
    case stacked
    /// Down the screen, squeezed when the column would run past the pile below it or the bottom of the board.
    case down
    /// The top `visible` cards side by side to the right (Klondike's draw-3 waste).
    case right(visible: Int)
}

/// The outline marking a pile while it is empty.
enum SlotMark: Equatable {
    case blank
    case text(String)
    case symbol(String)
}

/// Where one pile sits, in card steps: `x` 0 is the leftmost column, `y` 0 the top row, 1 the row below.
/// Fractions are allowed, for piles that sit between columns or overlap.
struct PileSpot {
    let pile: Pile
    let x: CGFloat
    let y: CGFloat
    let fan: Fan
    /// Drawn while the pile is empty; `nil` draws nothing there.
    let slot: SlotMark?
    /// Dragged cards can land here.
    let isDropTarget: Bool

    init(_ pile: Pile, x: CGFloat, y: CGFloat, fan: Fan = .stacked, slot: SlotMark? = .blank, isDropTarget: Bool = true) {
        self.pile = pile
        self.x = x
        self.y = y
        self.fan = fan
        self.slot = slot
        self.isDropTarget = isDropTarget
    }
}

/// A game's board: how many card columns wide it is and where its piles go. VoiceOver reads the piles
/// in the order of `spots`.
struct BoardSpec {
    /// Width in card columns. Past seven, cards get narrower and taller and their corner index bigger.
    let columns: Int
    /// Height the board needs, in card heights, so on wide screens a long column keeps its corner indexes
    /// readable instead of squeezing.
    var heightInCards: CGFloat = 5.5
    let spots: [PileSpot]
}

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
    let board: BoardSpec
    let spacing: CGFloat
    let cardSize: CGSize
    /// Left edge of the first column; centres the columns on wide screens.
    let inset: CGFloat
    /// How much bigger the corner index is drawn: narrow cards keep it readable.
    let indexScale: CGFloat

    init(size: CGSize, board: BoardSpec) {
        self.size = size
        self.board = board
        let columns = CGFloat(board.columns)
        let isNarrow = board.columns > 7
        let aspect: CGFloat = isNarrow ? 1.55 : 1.4
        let spacing = max(4, min(size.width, size.height) * 0.015)
        let byWidth = (size.width - spacing * (columns + 1)) / columns
        let byHeight = (size.height - spacing * 4) / (aspect * board.heightInCards)
        let width = max(10, min(byWidth, byHeight))
        self.spacing = spacing
        cardSize = CGSize(width: width, height: width * aspect)
        inset = (size.width - (columns * width + (columns - 1) * spacing)) / 2
        indexScale = isNarrow ? 1 + (columns - 7) * 0.1 : 1
    }

    func x(column: CGFloat) -> CGFloat {
        inset + column * (cardSize.width + spacing) + cardSize.width / 2
    }

    /// The top edge of a row.
    func top(row: CGFloat) -> CGFloat {
        spacing + row * (cardSize.height + spacing * 2)
    }

    func slotCenter(_ pile: Pile) -> CGPoint {
        guard let spot = spot(pile) else { return .zero }
        return center(spot)
    }

    /// The pile a card dropped with its centre at `point` lands on: the lowest pile in that column whose
    /// row starts above the point.
    func pile(at point: CGPoint) -> Pile? {
        let reach = (cardSize.width + spacing) / 2
        let candidates = board.spots.filter { spot in
            abs(point.x - x(column: spot.x)) <= reach && (spot.y == 0 || point.y >= top(row: spot.y) - spacing)
        }
        let hit = candidates.max { a, b in
            a.y != b.y ? a.y < b.y : abs(point.x - x(column: a.x)) > abs(point.x - x(column: b.x))
        }
        guard let hit, hit.isDropTarget else { return nil }
        return hit.pile
    }

    func place(_ game: AnyGame, raised: Set<Int>) -> [PlacedCard] {
        var result: [PlacedCard] = []
        result.reserveCapacity(52)

        func add(_ card: Card, _ pile: Pile, _ index: Int, _ center: CGPoint) {
            let z = Double(index) + (raised.contains(card.id) ? 100 : 0)
            result.append(PlacedCard(card: card, pile: pile, index: index, center: center, zIndex: z))
        }

        for spot in board.spots {
            let cards = game.cards(in: spot.pile)
            let origin = center(spot)
            switch spot.fan {
            case .stacked:
                for (i, card) in cards.enumerated() { add(card, spot.pile, i, origin) }
            case .right(let visible):
                let fan = cardSize.width * 0.28
                let fanned = min(visible, cards.count)
                for (i, card) in cards.enumerated() {
                    var center = origin
                    center.x += CGFloat(max(0, i - (cards.count - fanned))) * fan
                    add(card, spot.pile, i, center)
                }
            case .down:
                let offsets = downOffsets(cards, from: spot)
                for (i, card) in cards.enumerated() {
                    add(card, spot.pile, i, CGPoint(x: origin.x, y: origin.y + offsets[i]))
                }
            }
        }
        return result
    }

    // MARK: - Private

    private func spot(_ pile: Pile) -> PileSpot? {
        board.spots.first { $0.pile == pile }
    }

    func center(_ spot: PileSpot) -> CGPoint {
        CGPoint(x: x(column: spot.x), y: top(row: spot.y) + cardSize.height / 2)
    }

    /// Vertical offset of each card in a column, squeezed when the column would run past the pile below it
    /// or off the screen.
    private func downOffsets(_ column: [Card], from spot: PileSpot) -> [CGFloat] {
        let steps = column.dropLast().map { $0.isFaceUp ? cardSize.height * 0.31 : cardSize.height * 0.12 }
        let total = steps.reduce(0, +)
        let below = board.spots.filter { abs($0.x - spot.x) < 0.5 && $0.y > spot.y }.map { top(row: $0.y) - spacing }.min()
        let available = max(0, (below ?? size.height) - top(row: spot.y) - cardSize.height - spacing)
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
