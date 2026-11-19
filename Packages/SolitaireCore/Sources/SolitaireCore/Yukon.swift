/// Yukon has no rule options yet. To add one, give it a stored property with its default value here.
public struct YukonOptions: GameOptions {
    public init() {}
}

/// Yukon: seven columns, no stock. Any face-up card moves with everything on top of it onto a card one rank
/// higher in the opposite colour; an empty column takes kings.
public struct Yukon: SolitaireGame {
    public static let kind = GameKind.yukon
    public static let foundationCount = 4
    public static let tableauCount = 7

    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let options: YukonOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: YukonOptions = YukonOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck
        deck.deterministicShuffle(using: &rng)
        // Column 1 gets one face-up card; column n gets n - 1 face-down cards, then five face-up.
        var tableau: [[Card]] = []
        for column in 0..<Self.tableauCount {
            let count = column == 0 ? 1 : column + 5
            let hidden = column == 0 ? 0 : column
            var cards = Array(deck.suffix(count))
            deck.removeLast(count)
            for i in hidden..<cards.count { cards[i].isFaceUp = true }
            tableau.append(cards)
        }
        self.init(foundations: Array(repeating: [], count: Self.foundationCount), tableau: tableau, options: options, seed: seed)
    }

    init(foundations: [[Card]], tableau: [[Card]], options: YukonOptions = YukonOptions(), seed: UInt64 = 0) {
        self.foundations = foundations
        self.tableau = tableau
        self.options = options
        self.seed = seed
    }

    // MARK: - Queries

    public var piles: [Pile] {
        (0..<Self.foundationCount).map(Pile.foundation) + (0..<Self.tableauCount).map(Pile.tableau)
    }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock, .waste, .cell: []
        case .foundation(let i): foundations.indices.contains(i) ? foundations[i] : []
        case .tableau(let i): tableau.indices.contains(i) ? tableau[i] : []
        }
    }

    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    /// Everything is face up and every column runs down in rank, so the lowest card left can always go up next.
    public var canAutoComplete: Bool {
        !isWon && tableau.allSatisfy { column in
            column.allSatisfy(\.isFaceUp) && zip(column, column.dropFirst()).allSatisfy { $0.rank >= $1.rank }
        }
    }

    /// Whether `upper` can sit on `lower`: one rank down, opposite colour.
    static func connects(_ upper: Card, onto lower: Card) -> Bool {
        lower.isFaceUp && upper.rank == lower.rank - 1 && upper.suit.isRed != lower.suit.isRed
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, isValid(destination), canPickUp(from: source, at: index) else { return false }
        let sourceCards = cards(in: source)
        let card = sourceCards[index]
        switch destination {
        case .foundation(let f):
            return !source.isFoundation && index == sourceCards.count - 1 && fits(card, on: foundations[f])
        case .tableau(let t):
            guard let top = tableau[t].last else { return card.rank == 13 }
            return Self.connects(card, onto: top)
        default:
            return false
        }
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination) else { return false }
        var sourceCards = cards(in: source)
        let moving = Array(sourceCards[index...])
        sourceCards.removeSubrange(index...)
        if case .tableau = source, let last = sourceCards.indices.last { sourceCards[last].isFaceUp = true }
        set(sourceCards, in: source)
        set(cards(in: destination) + moving, in: destination)
        moveCount += 1
        return true
    }

    // MARK: - Private

    func fits(_ card: Card, on foundation: [Card]) -> Bool {
        guard let top = foundation.last else { return card.rank == 1 }
        return top.suit == card.suit && card.rank == top.rank + 1
    }

    func fitsFoundation(_ card: Card) -> Bool {
        foundations.contains { fits(card, on: $0) }
    }

    private func isValid(_ pile: Pile) -> Bool {
        switch pile {
        case .stock, .waste, .cell: false
        case .foundation(let i): foundations.indices.contains(i)
        case .tableau(let i): tableau.indices.contains(i)
        }
    }

    private mutating func set(_ cards: [Card], in pile: Pile) {
        switch pile {
        case .foundation(let i): foundations[i] = cards
        case .tableau(let i): tableau[i] = cards
        default: break
        }
    }
}

// MARK: - Hint

extension Yukon {
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move)
    }

    /// Moves that make progress, best first: a card onto a foundation (lowest first); a move that turns up a
    /// face-down card (the column with most hidden cards first); the cards over a card the foundations need;
    /// a whole column onto another, which empties it; anything else that joins cards. A move that only splits
    /// a card from the card it already sits on is left out, so the hint never shuffles back and forth, and with
    /// no useful move left the game is stuck.
    public var usefulMoves: [Move] {
        var moves: [Move] = []
        func add(_ source: Pile, _ index: Int, to destination: Pile) {
            let move = Move(from: source, index: index, to: destination)
            if canApply(move), !moves.contains(move) { moves.append(move) }
        }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        let filled = columns.filter { !cards(in: $0).isEmpty }

        // 1. Foundations.
        let tops = filled.map { (pile: $0, index: cards(in: $0).count - 1) }
        for top in tops.sorted(by: { cards(in: $0.pile)[$0.index].rank < cards(in: $1.pile)[$1.index].rank }) {
            if let foundation = foundationDestination(from: top.pile, at: top.index) { add(top.pile, top.index, to: foundation) }
        }

        // 2. Turn up a face-down card.
        let hiddenCount = { (column: Pile) in cards(in: column).prefix { !$0.isFaceUp }.count }
        for column in filled.sorted(by: { hiddenCount($0) > hiddenCount($1) }) where hiddenCount(column) > 0 {
            for destination in columns { add(column, hiddenCount(column), to: destination) }
        }

        // 3. Free a card the foundations need.
        let buried: [(column: Pile, index: Int)] = filled.compactMap { column in
            let cards = cards(in: column)
            guard let index = cards.dropLast().lastIndex(where: { $0.isFaceUp && fitsFoundation($0) }) else { return nil }
            return (column, index + 1)
        }
        .sorted { cards(in: $0.column).count - $0.index < cards(in: $1.column).count - $1.index }
        for (column, index) in buried {
            for destination in columns where destination != column { add(column, index, to: destination) }
        }

        // 4. Empty a column, then any other move that joins cards.
        for column in filled {
            for destination in filled where destination != column { add(column, 0, to: destination) }
        }
        for column in filled {
            let cards = cards(in: column)
            for index in cards.indices.dropFirst() where cards[index].isFaceUp {
                guard !Self.connects(cards[index], onto: cards[index - 1]) else { continue }
                for destination in columns { add(column, index, to: destination) }
            }
        }
        return moves
    }
}
