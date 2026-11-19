/// Scorpion has no rule options yet. To add one, give it a stored property with its default value here.
public struct ScorpionOptions: GameOptions {
    public init() {}
}

/// Scorpion: seven columns of seven and a reserve of three. Build down in the same suit; any face-up card moves
/// with everything on top of it. A complete king-to-ace run leaves for a foundation by itself.
/// The reserve is the `.stock`: tapping it deals one card onto each of the first three columns, once.
public struct Scorpion: SolitaireGame {
    public static let kind = GameKind.scorpion
    public static let foundationCount = 4
    public static let tableauCount = 7
    static let reserveCount = 3

    public private(set) var stock: [Card]
    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let options: ScorpionOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: ScorpionOptions = ScorpionOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck
        deck.deterministicShuffle(using: &rng)
        // Columns 1 to 4 start with three face-down cards, then four face up; columns 5 to 7 are all face up.
        var tableau: [[Card]] = []
        for column in 0..<Self.tableauCount {
            var cards = Array(deck.suffix(7))
            deck.removeLast(7)
            for i in (column < 4 ? 3 : 0)..<cards.count { cards[i].isFaceUp = true }
            tableau.append(cards)
        }
        self.init(stock: deck, foundations: Array(repeating: [], count: Self.foundationCount), tableau: tableau, options: options, seed: seed)
    }

    init(stock: [Card], foundations: [[Card]], tableau: [[Card]], options: ScorpionOptions = ScorpionOptions(), seed: UInt64 = 0) {
        self.stock = stock
        self.foundations = foundations
        self.tableau = tableau
        self.options = options
        self.seed = seed
    }

    // MARK: - Queries

    public var piles: [Pile] {
        [.stock] + (0..<Self.foundationCount).map(Pile.foundation) + (0..<Self.tableauCount).map(Pile.tableau)
    }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: stock
        case .waste, .cell: []
        case .foundation(let i): foundations.indices.contains(i) ? foundations[i] : []
        case .tableau(let i): tableau.indices.contains(i) ? tableau[i] : []
        }
    }

    /// Four runs removed.
    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    public var canAutoComplete: Bool { false }

    /// A face-up card in a column, with everything on it. Finished runs stay on the foundations.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        let cards = cards(in: pile)
        return pile.isTableau && cards.indices.contains(index) && cards[index].isFaceUp
    }

    /// Whether `upper` can sit on `lower`: one rank down, same suit.
    static func connects(_ upper: Card, onto lower: Card) -> Bool {
        lower.isFaceUp && upper.rank == lower.rank - 1 && upper.suit == lower.suit
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, case .tableau(let t) = destination, tableau.indices.contains(t),
              canPickUp(from: source, at: index) else { return false }
        let card = cards(in: source)[index]
        guard let top = tableau[t].last else { return card.rank == 13 }
        return Self.connects(card, onto: top)
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination),
              case .tableau(let from) = source, case .tableau(let to) = destination else { return false }
        tableau[to] += tableau[from][index...]
        tableau[from].removeSubrange(index...)
        finishMove()
        return true
    }

    /// Deals the reserve: one card face up onto each of the first three columns.
    @discardableResult
    public mutating func draw() -> Bool {
        guard stock.count >= Self.reserveCount else { return false }
        for column in 0..<Self.reserveCount {
            var card = stock.removeLast()
            card.isFaceUp = true
            tableau[column].append(card)
        }
        finishMove()
        return true
    }

    // MARK: - Private

    /// Counts the move, sends complete runs to the foundations and turns up what they uncover.
    private mutating func finishMove() {
        moveCount += 1
        for column in tableau.indices {
            let cards = tableau[column]
            guard cards.count >= 13, let slot = foundations.firstIndex(where: \.isEmpty) else { continue }
            let run = cards.suffix(13)
            guard run.first?.rank == 13, run.allSatisfy({ $0.isFaceUp }),
                  zip(run, run.dropFirst()).allSatisfy({ Self.connects($1, onto: $0) }) else { continue }
            foundations[slot] = Array(run)
            tableau[column].removeLast(13)
        }
        for column in tableau.indices {
            if let last = tableau[column].indices.last { tableau[column][last].isFaceUp = true }
        }
    }
}

// MARK: - Hint

extension Scorpion {
    /// The best move; `.draw` when only the reserve can help; `nil` when nothing helps.
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move) ?? (stock.isEmpty ? nil : .draw)
    }

    /// Moves that make progress, best first: a move that completes a run; one that turns up a face-down card
    /// (the column with most hidden cards first); a whole column onto another, which empties it; anything else
    /// that joins cards. A move that only splits a card from the card it already sits on is left out, so the
    /// hint never shuffles back and forth.
    public var usefulMoves: [Move] {
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        var candidates: [Move] = []
        for column in columns {
            let cards = cards(in: column)
            for index in cards.indices where cards[index].isFaceUp {
                // Already joined to the card below, or already at the bottom of a column: moving gains nothing,
                // except as a king to an empty column (index > 0).
                if index > 0, Self.connects(cards[index], onto: cards[index - 1]) { continue }
                for destination in columns {
                    let move = Move(from: column, index: index, to: destination)
                    if index == 0, self.cards(in: destination).isEmpty { continue }
                    if canApply(move) { candidates.append(move) }
                }
            }
        }
        func rank(_ move: Move) -> Int {
            var after = self
            after.apply(move)
            if after.foundations.filter({ !$0.isEmpty }).count > foundations.filter({ !$0.isEmpty }).count { return 0 }
            if move.index > 0, !cards(in: move.from)[move.index - 1].isFaceUp { return 1 }
            return move.index == 0 ? 2 : 3
        }
        func hidden(_ move: Move) -> Int { cards(in: move.from).prefix { !$0.isFaceUp }.count }
        return candidates.enumerated()
            .sorted { a, b in
                let (ra, rb) = (rank(a.element), rank(b.element))
                if ra != rb { return ra < rb }
                if ra == 1, hidden(a.element) != hidden(b.element) { return hidden(a.element) > hidden(b.element) }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}
