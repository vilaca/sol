/// Baker's Dozen has no rule options. To add one, give it a stored property with its default value here
/// (and a row in the app's `BakersDozen.ruleSettings`); saves from before decode it as that default.
public struct BakersDozenOptions: GameOptions {
    public init() {}
}

/// Baker's Dozen: thirteen columns of four cards, all face up, kings dealt to the bottom of their column.
/// Cards build down in any suit, one at a time, and an empty column stays empty.
public struct BakersDozen: SolitaireGame {
    public static let kind = GameKind.bakersDozen
    public static let foundationCount = 4
    public static let tableauCount = 13

    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let options: BakersDozenOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: BakersDozenOptions = BakersDozenOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck.map { Card(suit: $0.suit, rank: $0.rank, isFaceUp: true) }
        deck.deterministicShuffle(using: &rng)
        let columns = (0..<Self.tableauCount).map { Array(deck[($0 * 4)..<($0 * 4 + 4)]) }
        // Kings go to the bottom (first card) of their column, so none is buried under a card it blocks.
        let tableau = columns.map { column in column.filter { $0.rank == 13 } + column.filter { $0.rank != 13 } }
        self.init(foundations: Array(repeating: [], count: Self.foundationCount), tableau: tableau, options: options, seed: seed)
    }

    init(foundations: [[Card]], tableau: [[Card]], options: BakersDozenOptions = BakersDozenOptions(), seed: UInt64 = 0) {
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

    /// Every column runs down in rank, so the lowest card left can always go up next.
    public var canAutoComplete: Bool {
        !isWon && tableau.allSatisfy { column in zip(column, column.dropFirst()).allSatisfy { $0.rank >= $1.rank } }
    }

    /// Only the top card of a column moves, one at a time.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        guard case .tableau = pile else { return false }
        let cards = cards(in: pile)
        return !cards.isEmpty && index == cards.count - 1
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, isValid(destination), canPickUp(from: source, at: index) else { return false }
        let card = cards(in: source)[index]
        switch destination {
        case .foundation(let f):
            guard let top = foundations[f].last else { return card.rank == 1 }
            return top.suit == card.suit && card.rank == top.rank + 1
        case .tableau(let t):
            // Nothing goes on an empty column.
            guard let top = tableau[t].last else { return false }
            return card.rank == top.rank - 1
        default:
            return false
        }
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination) else { return false }
        let card = cards(in: source)[index]
        switch source {
        case .tableau(let i): tableau[i].removeLast()
        default: break
        }
        switch destination {
        case .foundation(let i): foundations[i].append(card)
        case .tableau(let i): tableau[i].append(card)
        default: break
        }
        moveCount += 1
        return true
    }

    // MARK: - Private

    private func isValid(_ pile: Pile) -> Bool {
        switch pile {
        case .foundation(let i): foundations.indices.contains(i)
        case .tableau(let i): tableau.indices.contains(i)
        default: false
        }
    }

    func fitsFoundation(_ card: Card) -> Bool {
        foundations.contains { foundation in
            foundation.last.map { $0.suit == card.suit && card.rank == $0.rank + 1 } ?? (card.rank == 1)
        }
    }
}

// MARK: - Hint

extension BakersDozen {
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move)
    }

    /// Moves that make progress, best first: a card onto a foundation (lowest first); a card off a column
    /// that holds a card the foundations need, fewest cards on top first; then a card onto the one just
    /// above it in rank that doesn't bury a needed card; last, one that does. A card that already sits on the
    /// next rank up stays: moving it to another card of the same rank gets nowhere. Every other move adds
    /// such a pair and no move breaks one, so following the hint can't go round in circles.
    public var usefulMoves: [Move] {
        var moves: [Move] = []
        func add(_ source: Pile, to destination: Pile) {
            guard let index = cards(in: source).indices.last else { return }
            let move = Move(from: source, index: index, to: destination)
            if canApply(move), !moves.contains(move) { moves.append(move) }
        }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        let filled = columns.filter { !cards(in: $0).isEmpty }
        // Columns with a card the foundations need under other cards, with the cards above it.
        let buried: [(column: Pile, above: Int)] = filled.compactMap { column in
            let cards = cards(in: column)
            guard let index = cards.dropLast().lastIndex(where: fitsFoundation) else { return nil }
            return (column, cards.count - 1 - index)
        }
        .sorted { $0.above < $1.above }
        let burying = Set(buried.map(\.column))
        /// The top card already rests on the next rank up (or is alone).
        func isSettled(_ column: Pile) -> Bool {
            let cards = cards(in: column)
            guard cards.count > 1 else { return true }
            return cards[cards.count - 2].rank == cards[cards.count - 1].rank + 1
        }

        // 1. A card onto a foundation, lowest first.
        for column in filled.sorted(by: { cards(in: $0).last!.rank < cards(in: $1).last!.rank }) {
            if let index = cards(in: column).indices.last, let foundation = foundationDestination(from: column, at: index) {
                add(column, to: foundation)
            }
        }
        // 2. The top card off a column that buries a needed card.
        for (column, _) in buried {
            for destination in filled where destination != column && !burying.contains(destination) { add(column, to: destination) }
        }
        // 3. A card onto the next rank up, where it buries nothing needed.
        for column in filled where !isSettled(column) && !burying.contains(column) {
            for destination in filled where destination != column && !burying.contains(destination) { add(column, to: destination) }
        }
        // 4. The same, onto a column that holds a needed card.
        for column in filled where !isSettled(column) {
            for destination in filled where destination != column { add(column, to: destination) }
        }
        return moves
    }
}
