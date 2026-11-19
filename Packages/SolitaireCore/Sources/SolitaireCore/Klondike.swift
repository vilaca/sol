/// Draw 1 or draw 3, chosen in the New menu or in Settings.
public struct KlondikeOptions: GameOptions {
    public var drawCount = 1

    public init() {}

    public init(drawCount: Int) {
        self.drawCount = drawCount
    }
}

/// Klondike solitaire rules and state. A value type, so undo is just keeping old copies.
public struct Klondike: SolitaireGame {
    public static let kind = GameKind.klondike
    public static let foundationCount = 4
    public static let tableauCount = 7

    /// The last element of every pile is its top card.
    public private(set) var stock: [Card]
    public private(set) var waste: [Card]
    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let drawCount: Int
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, drawCount: Int = 1) {
        precondition(drawCount == 1 || drawCount == 3, "drawCount must be 1 or 3")
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck
        deck.deterministicShuffle(using: &rng)

        var tableau: [[Card]] = []
        for column in 0..<Self.tableauCount {
            var cards = Array(deck.suffix(column + 1))
            deck.removeLast(column + 1)
            cards[cards.count - 1].isFaceUp = true
            tableau.append(cards)
        }

        self.init(
            stock: deck,
            waste: [],
            foundations: Array(repeating: [], count: Self.foundationCount),
            tableau: tableau,
            drawCount: drawCount,
            seed: seed
        )
    }

    /// Options read from a damaged save deal draw 1 rather than trap.
    public init(seed: UInt64, options: KlondikeOptions) {
        self.init(seed: seed, drawCount: options.drawCount == 3 ? 3 : 1)
    }

    init(stock: [Card], waste: [Card], foundations: [[Card]], tableau: [[Card]], drawCount: Int = 1, seed: UInt64 = 0) {
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
        self.drawCount = drawCount
        self.seed = seed
    }

    // MARK: - Queries

    public var options: KlondikeOptions { KlondikeOptions(drawCount: drawCount) }

    public var piles: [Pile] {
        [.stock, .waste] + (0..<Self.foundationCount).map(Pile.foundation) + (0..<Self.tableauCount).map(Pile.tableau)
    }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: stock
        case .waste: waste
        case .foundation(let i): foundations[i]
        case .tableau(let i): tableau[i]
        case .cell: []
        }
    }

    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    /// Nothing hidden and nothing left to draw: the game can finish itself.
    public var canAutoComplete: Bool {
        !isWon && stock.isEmpty && waste.isEmpty && tableau.allSatisfy { $0.allSatisfy(\.isFaceUp) }
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, isValid(source), isValid(destination) else { return false }
        let sourceCards = cards(in: source)
        guard sourceCards.indices.contains(index), sourceCards[index].isFaceUp else { return false }
        let movingCount = sourceCards.count - index

        switch source {
        case .stock, .cell:
            return false
        case .waste, .foundation:
            guard movingCount == 1 else { return false }
        case .tableau:
            break
        }

        let card = sourceCards[index]
        switch destination {
        case .stock, .waste, .cell:
            return false
        case .foundation(let f):
            guard movingCount == 1 else { return false }
            guard let top = foundations[f].last else { return card.rank == 1 }
            return top.suit == card.suit && card.rank == top.rank + 1
        case .tableau(let t):
            guard let top = tableau[t].last else { return card.rank == 13 }
            return top.isFaceUp && top.suit.isRed != card.suit.isRed && card.rank == top.rank - 1
        }
    }

    // MARK: - Actions

    /// Turns stock cards onto the waste, or recycles the waste when the stock is empty.
    @discardableResult
    public mutating func draw() -> Bool {
        if stock.isEmpty {
            guard !waste.isEmpty else { return false }
            stock = waste.reversed().map { card in
                var card = card
                card.isFaceUp = false
                return card
            }
            waste = []
        } else {
            for _ in 0..<min(drawCount, stock.count) {
                var card = stock.removeLast()
                card.isFaceUp = true
                waste.append(card)
            }
        }
        moveCount += 1
        return true
    }

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination) else { return false }
        var sourceCards = cards(in: source)
        let moving = Array(sourceCards[index...])
        sourceCards.removeSubrange(index...)
        if case .tableau = source, let last = sourceCards.indices.last, !sourceCards[last].isFaceUp {
            sourceCards[last].isFaceUp = true
        }
        set(sourceCards, in: source)
        set(cards(in: destination) + moving, in: destination)
        moveCount += 1
        return true
    }

    // MARK: - Private

    private func isValid(_ pile: Pile) -> Bool {
        switch pile {
        case .stock, .waste: true
        case .foundation(let i): (0..<Self.foundationCount).contains(i)
        case .tableau(let i): (0..<Self.tableauCount).contains(i)
        case .cell: false
        }
    }

    private mutating func set(_ cards: [Card], in pile: Pile) {
        switch pile {
        case .stock: stock = cards
        case .waste: waste = cards
        case .foundation(let i): foundations[i] = cards
        case .tableau(let i): tableau[i] = cards
        case .cell: break
        }
    }
}

