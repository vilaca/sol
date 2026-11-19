/// Forty Thieves has no rule options yet. To add one, give it a stored property with its default value here.
public struct FortyThievesOptions: GameOptions {
    public init() {}
}

/// Forty Thieves: two decks, ten columns of four cards (all face up), a stock of 64 and eight foundations.
/// Build down in the same suit, one card at a time; an empty column takes any card. The stock turns one card
/// onto the waste, once through: there is no redeal. Won when all 104 cards are on the foundations.
public struct FortyThieves: SolitaireGame {
    public static let kind = GameKind.fortyThieves
    public static let recyclesWaste = false
    public static let foundationCount = 8
    public static let tableauCount = 10

    public private(set) var stock: [Card]
    public private(set) var waste: [Card]
    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let options: FortyThievesOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: FortyThievesOptions = FortyThievesOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = (0...1).flatMap { copy in Card.fullDeck.map { Card(suit: $0.suit, rank: $0.rank, deck: copy) } }
        deck.deterministicShuffle(using: &rng)
        var tableau: [[Card]] = []
        for _ in 0..<Self.tableauCount {
            var cards = Array(deck.suffix(4))
            deck.removeLast(4)
            for i in cards.indices { cards[i].isFaceUp = true }
            tableau.append(cards)
        }
        self.init(stock: deck, waste: [], foundations: Array(repeating: [], count: Self.foundationCount), tableau: tableau, options: options, seed: seed)
    }

    init(stock: [Card], waste: [Card], foundations: [[Card]], tableau: [[Card]], options: FortyThievesOptions = FortyThievesOptions(), seed: UInt64 = 0) {
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
        self.options = options
        self.seed = seed
    }

    // MARK: - Queries

    public var piles: [Pile] {
        [.stock, .waste] + (0..<Self.foundationCount).map(Pile.foundation) + (0..<Self.tableauCount).map(Pile.tableau)
    }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: stock
        case .waste: waste
        case .cell: []
        case .foundation(let i): foundations.indices.contains(i) ? foundations[i] : []
        case .tableau(let i): tableau.indices.contains(i) ? tableau[i] : []
        }
    }

    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    /// Whether playing every card that can go up (lowest first, never touching the stock) wins. Checked by playing it.
    public var canAutoComplete: Bool {
        guard !isWon, stock.isEmpty else { return false }
        var game = self
        while let move = game.nextAutoMove() { game.apply(move) }
        return game.isWon
    }

    /// Only the top card of a column or of the waste can be played. Foundation cards stay there.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        switch pile {
        case .waste: return index >= 0 && index == waste.count - 1
        case .tableau(let i): return tableau.indices.contains(i) && index >= 0 && index == tableau[i].count - 1
        default: return false
        }
    }

    /// Whether `card` goes onto a foundation: an ace on an empty one, else the next rank of the pile's suit.
    static func fits(_ card: Card, onFoundation pile: [Card]) -> Bool {
        guard let top = pile.last else { return card.rank == 1 }
        return top.suit == card.suit && card.rank == top.rank + 1
    }

    /// Whether `card` goes onto a column: any card on an empty one, else the next rank down in the same suit.
    static func fits(_ card: Card, onColumn column: [Card]) -> Bool {
        guard let top = column.last else { return true }
        return top.suit == card.suit && card.rank == top.rank - 1
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, canPickUp(from: source, at: index) else { return false }
        let card = cards(in: source)[index]
        switch destination {
        case .foundation(let f): return foundations.indices.contains(f) && Self.fits(card, onFoundation: foundations[f])
        case .tableau(let t): return tableau.indices.contains(t) && Self.fits(card, onColumn: tableau[t])
        default: return false
        }
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination) else { return false }
        let card: Card
        switch source {
        case .waste: card = waste.removeLast()
        case .tableau(let i): card = tableau[i].removeLast()
        default: return false
        }
        switch destination {
        case .foundation(let f): foundations[f].append(card)
        case .tableau(let t): tableau[t].append(card)
        default: break
        }
        moveCount += 1
        return true
    }

    /// Turns the next stock card onto the waste. There is no redeal.
    @discardableResult
    public mutating func draw() -> Bool {
        guard var card = stock.popLast() else { return false }
        card.isFaceUp = true
        waste.append(card)
        moveCount += 1
        return true
    }
}

// MARK: - Hint

extension FortyThieves {
    /// The best move; `.draw` when only the stock can help; with the stock empty, the waste card onto an empty
    /// column as a last resort; `nil` when nothing helps.
    public var hint: Hint? {
        if let move = usefulMoves.first { return .move(move) }
        if !stock.isEmpty { return .draw }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        if let top = waste.indices.last, let empty = columns.first(where: { cards(in: $0).isEmpty }) {
            return .move(Move(from: .waste, index: top, to: empty))
        }
        return nil
    }

    /// Moves that make progress, best first: a card onto a foundation (the waste first); a top card out of the
    /// way of the card under it when that one can go to a foundation; the waste card onto a column in its suit;
    /// a column's top card onto the same suit, a lone card first (it empties its column). A card never leaves the
    /// card of its own suit it sits on, so the hint doesn't shuffle back and forth.
    public var usefulMoves: [Move] {
        var moves: [Move] = []
        func add(_ source: Pile, _ index: Int, to destination: Pile) {
            let move = Move(from: source, index: index, to: destination)
            if canApply(move), !moves.contains(move) { moves.append(move) }
        }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        let foundations = (0..<Self.foundationCount).map(Pile.foundation)
        let tops = ([Pile.waste] + columns).compactMap { pile in cards(in: pile).indices.last.map { (pile, $0) } }

        // 1. A card onto a foundation. An ace goes to the first empty one.
        for (pile, index) in tops {
            if let foundation = foundations.first(where: { canMove(from: pile, at: index, to: $0) }) {
                add(pile, index, to: foundation)
            }
        }

        // 2. A top card moved off the card that can go up.
        for column in columns {
            let cards = cards(in: column)
            guard cards.count >= 2, fitsAFoundation(cards[cards.count - 2]), !sitsOnItsSuit(column) else { continue }
            let top = cards.count - 1
            for destination in columns where destination != column && !self.cards(in: destination).isEmpty { add(column, top, to: destination) }
            for destination in columns where destination != column && self.cards(in: destination).isEmpty { add(column, top, to: destination) }
        }

        // 3. The waste card onto a column, in its suit.
        if let top = waste.indices.last {
            for column in columns where !cards(in: column).isEmpty { add(.waste, top, to: column) }
        }

        // 4. A column's top card onto the same suit; a lone card (emptying its column) before the others.
        let joins = columns.filter { !sitsOnItsSuit($0) }
            .sorted { cards(in: $0).count < cards(in: $1).count }
        for column in joins {
            let top = cards(in: column).count - 1
            for destination in columns where destination != column && !cards(in: destination).isEmpty { add(column, top, to: destination) }
        }
        return moves
    }

    /// Whether the top card of the column sits on the next card up of its own suit.
    private func sitsOnItsSuit(_ column: Pile) -> Bool {
        let cards = cards(in: column)
        guard cards.count >= 2 else { return false }
        let (top, below) = (cards[cards.count - 1], cards[cards.count - 2])
        return below.suit == top.suit && below.rank == top.rank + 1
    }

    private func fitsAFoundation(_ card: Card) -> Bool {
        foundations.contains { Self.fits(card, onFoundation: $0) }
    }
}
