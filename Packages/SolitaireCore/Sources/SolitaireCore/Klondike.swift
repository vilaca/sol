public enum Pile: Hashable, Codable, Sendable {
    case stock
    case waste
    case foundation(Int)
    case tableau(Int)
}

public struct Move: Hashable, Sendable {
    public let from: Pile
    /// Index of the first moved card in the source pile; every card above it moves too.
    public let index: Int
    public let to: Pile

    public init(from: Pile, index: Int, to: Pile) {
        self.from = from
        self.index = index
        self.to = to
    }
}

/// Klondike solitaire rules and state. A value type, so undo is just keeping old copies.
public struct Klondike: Codable, Equatable, Sendable {
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

    init(stock: [Card], waste: [Card], foundations: [[Card]], tableau: [[Card]], drawCount: Int = 1, seed: UInt64 = 0) {
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
        self.drawCount = drawCount
        self.seed = seed
    }

    // MARK: - Queries

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: stock
        case .waste: waste
        case .foundation(let i): foundations[i]
        case .tableau(let i): tableau[i]
        }
    }

    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    /// Nothing hidden and nothing left to draw: the game can finish itself.
    public var canAutoComplete: Bool {
        !isWon && stock.isEmpty && waste.isEmpty && tableau.allSatisfy { $0.allSatisfy(\.isFaceUp) }
    }

    /// Which pile each card is in, keyed by `Card.id`.
    public var pileByCard: [Int: Pile] {
        var result: [Int: Pile] = [:]
        for card in stock { result[card.id] = .stock }
        for card in waste { result[card.id] = .waste }
        for (i, pile) in foundations.enumerated() {
            for card in pile { result[card.id] = .foundation(i) }
        }
        for (i, pile) in tableau.enumerated() {
            for card in pile { result[card.id] = .tableau(i) }
        }
        return result
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, isValid(source), isValid(destination) else { return false }
        let sourceCards = cards(in: source)
        guard sourceCards.indices.contains(index), sourceCards[index].isFaceUp else { return false }
        let movingCount = sourceCards.count - index

        switch source {
        case .stock:
            return false
        case .waste, .foundation:
            guard movingCount == 1 else { return false }
        case .tableau:
            break
        }

        let card = sourceCards[index]
        switch destination {
        case .stock, .waste:
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

    public func canApply(_ move: Move) -> Bool {
        canMove(from: move.from, at: move.index, to: move.to)
    }

    /// The foundation this card can go to, if any.
    public func foundationDestination(from source: Pile, at index: Int) -> Pile? {
        (0..<Self.foundationCount).map(Pile.foundation).first { canMove(from: source, at: index, to: $0) }
    }

    /// The pile a tap on this card should send it to: a foundation first, then a non-empty column, then an empty one.
    public func bestDestination(from source: Pile, at index: Int) -> Pile? {
        if !source.isFoundation, let foundation = foundationDestination(from: source, at: index) {
            return foundation
        }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        if let column = columns.first(where: { !cards(in: $0).isEmpty && canMove(from: source, at: index, to: $0) }) {
            return column
        }
        // A king already at the bottom of a column gains nothing from moving to another empty column.
        if case .tableau = source, index == 0 { return nil }
        return columns.first { cards(in: $0).isEmpty && canMove(from: source, at: index, to: $0) }
    }

    /// The next card that can go to a foundation, lowest rank first.
    public func nextAutoMove() -> Move? {
        var candidates: [Move] = []
        if !waste.isEmpty {
            candidates.append(Move(from: .waste, index: waste.count - 1, to: .waste))
        }
        for (i, column) in tableau.enumerated() where !column.isEmpty {
            candidates.append(Move(from: .tableau(i), index: column.count - 1, to: .tableau(i)))
        }
        let sorted = candidates.sorted { cards(in: $0.from)[$0.index].rank < cards(in: $1.from)[$1.index].rank }
        for candidate in sorted {
            for f in 0..<Self.foundationCount where canMove(from: candidate.from, at: candidate.index, to: .foundation(f)) {
                return Move(from: candidate.from, index: candidate.index, to: .foundation(f))
            }
        }
        return nil
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

    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        self.move(from: move.from, at: move.index, to: move.to)
    }

    // MARK: - Private

    private func isValid(_ pile: Pile) -> Bool {
        switch pile {
        case .stock, .waste: true
        case .foundation(let i): (0..<Self.foundationCount).contains(i)
        case .tableau(let i): (0..<Self.tableauCount).contains(i)
        }
    }

    private mutating func set(_ cards: [Card], in pile: Pile) {
        switch pile {
        case .stock: stock = cards
        case .waste: waste = cards
        case .foundation(let i): foundations[i] = cards
        case .tableau(let i): tableau[i] = cards
        }
    }
}

extension Pile {
    public var isFoundation: Bool {
        if case .foundation = self { return true }
        return false
    }
}
