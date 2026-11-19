/// What the hint button suggests.
public enum Hint: Hashable, Sendable {
    case move(Move)
    /// Draw from the stock, or turn the waste over when the stock is empty.
    case draw
}

extension Klondike {
    /// The most useful move; `.draw` when only the stock can help; `nil` when nothing helps and the game is stuck.
    public var hint: Hint? {
        if let move = usefulMoves.first { return .move(move) }
        return stockCanHelp ? .draw : nil
    }

    /// Moves that make progress, best first. Shuffling cards between columns without uncovering
    /// anything is left out: it is legal, but it never gets the game closer to a win.
    public var usefulMoves: [Move] {
        var moves: [Move] = []
        func add(_ source: Pile, _ index: Int, to destination: Pile) {
            let move = Move(from: source, index: index, to: destination)
            if canApply(move), !moves.contains(move) { moves.append(move) }
        }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)

        // 1. A card onto a foundation.
        if let top = waste.indices.last, let foundation = foundationDestination(from: .waste, at: top) {
            add(.waste, top, to: foundation)
        }
        for column in columns {
            if let top = cards(in: column).indices.last, let foundation = foundationDestination(from: column, at: top) {
                add(column, top, to: foundation)
            }
        }

        // 2. A column move that turns a hidden card over, or that empties a column for a king.
        let kingsAtBottom = tableau.filter { $0.first?.rank == 13 }.count
        for (t, cards) in tableau.enumerated() {
            guard let first = cards.firstIndex(where: \.isFaceUp) else { continue }
            let uncovers = first > 0
            let freesColumn = first == 0 && cards[0].rank != 13 && kingsAtBottom < 4
            guard uncovers || freesColumn else { continue }
            for column in columns where column != .tableau(t) {
                add(.tableau(t), first, to: column)
            }
        }

        // 3. A column move that frees the card under it for a foundation.
        for (t, cards) in tableau.enumerated() {
            guard let first = cards.firstIndex(where: \.isFaceUp) else { continue }
            for i in cards.indices where i > first && fitsFoundation(cards[i - 1]) {
                for column in columns where column != .tableau(t) {
                    add(.tableau(t), i, to: column)
                }
            }
        }

        // 4. The waste card onto a column.
        if let top = waste.indices.last {
            for column in columns { add(.waste, top, to: column) }
        }
        return moves
    }

    /// Whether drawing (through the whole stock, turning the waste over as needed) brings up a card that can be played.
    private var stockCanHelp: Bool {
        var game = self
        // Two full passes: after one, the stock is back in the same order, so nothing new can come up.
        let passes = 2 * ((stock.count + waste.count) / drawCount + 2)
        for _ in 0..<passes {
            guard game.draw() else { return false }
            if let top = game.waste.indices.last,
               game.foundationDestination(from: .waste, at: top) != nil
               || (0..<Self.tableauCount).contains(where: { game.canMove(from: .waste, at: top, to: .tableau($0)) }) {
                return true
            }
        }
        return false
    }

    private func fitsFoundation(_ card: Card) -> Bool {
        foundations.contains { pile in
            if let top = pile.last { top.suit == card.suit && card.rank == top.rank + 1 } else { card.rank == 1 }
        }
    }
}
