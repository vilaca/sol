public struct SpiderOptions: GameOptions {
    /// How many suits are dealt: 1 (all spades), 2 (spades and hearts) or 4. A variant: each has its own statistics.
    public var suits = 1
    public init() {}
}

/// Spider: two decks' worth of cards (104) in ten columns, a stock of 50. Build down regardless of suit; only a run
/// of one suit moves together. Tapping the stock deals a card onto every column (none may be empty). A complete
/// king-to-ace run of one suit leaves for a foundation by itself; eight runs win.
///
/// With fewer than four suits the 104 cards are copies: one suit is eight copies of spades (`Card.deck` 0...7),
/// two suits four copies each of spades and hearts (0...3), so every card still has its own `id`.
public struct Spider: SolitaireGame {
    public static let kind = GameKind.spider
    public static let foundationCount = 8
    public static let tableauCount = 10

    public private(set) var stock: [Card]
    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let options: SpiderOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    /// 1, 2 or 4: anything else counts as 1.
    static func suitCount(_ options: SpiderOptions) -> Int {
        [2, 4].contains(options.suits) ? options.suits : 1
    }

    public init(seed: UInt64, options: SpiderOptions = SpiderOptions()) {
        var rng = SplitMix64(seed: seed)
        let suits = Self.suitCount(options)
        var deck = Suit.allCases.prefix(suits).flatMap { suit in
            (0..<(8 / suits)).flatMap { copy in (1...13).map { Card(suit: suit, rank: $0, deck: copy) } }
        }
        deck.deterministicShuffle(using: &rng)
        // The first four columns get six cards, the other six get five; only the last card of each is face up.
        var tableau: [[Card]] = []
        for column in 0..<Self.tableauCount {
            var cards = Array(deck.suffix(column < 4 ? 6 : 5))
            deck.removeLast(cards.count)
            cards[cards.count - 1].isFaceUp = true
            tableau.append(cards)
        }
        self.init(stock: deck, foundations: Array(repeating: [], count: Self.foundationCount), tableau: tableau, options: options, seed: seed)
    }

    init(stock: [Card], foundations: [[Card]], tableau: [[Card]], options: SpiderOptions = SpiderOptions(), seed: UInt64 = 0) {
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

    /// Eight runs removed.
    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    public var canAutoComplete: Bool { false }

    /// Whether `upper` can sit on `lower` in a column: one rank down, any suit.
    static func fits(_ upper: Card, on lower: Card) -> Bool {
        upper.rank == lower.rank - 1
    }

    /// Whether `upper` continues the run `lower` is in: one rank down, same suit.
    static func continues(_ upper: Card, _ lower: Card) -> Bool {
        fits(upper, on: lower) && upper.suit == lower.suit
    }

    /// A face-up card of a column that starts a same-suit run down to the column's last card.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        guard pile.isTableau else { return false }
        let cards = cards(in: pile)
        guard cards.indices.contains(index), cards[index...].allSatisfy({ $0.isFaceUp }) else { return false }
        return zip(cards[index...], cards[index...].dropFirst()).allSatisfy { Self.continues($1, $0) }
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, case .tableau(let t) = destination, tableau.indices.contains(t),
              canPickUp(from: source, at: index) else { return false }
        guard let top = tableau[t].last else { return true }
        return Self.fits(cards(in: source)[index], on: top)
    }

    /// Whether the stock can be dealt: it holds a row and no column is empty.
    public var canDeal: Bool {
        stock.count >= Self.tableauCount && !tableau.contains { $0.isEmpty }
    }

    /// A tap sends the card onto the same suit if it can, else onto any other column; an empty column only for
    /// a card that isn't already at the bottom of one.
    public func bestDestination(from source: Pile, at index: Int) -> Pile? {
        guard canPickUp(from: source, at: index) else { return nil }
        let suit = cards(in: source)[index].suit
        let columns = (0..<Self.tableauCount).map(Pile.tableau).filter { canMove(from: source, at: index, to: $0) }
        return columns.first { cards(in: $0).last?.suit == suit }
            ?? columns.first { !cards(in: $0).isEmpty }
            ?? (index == 0 ? nil : columns.first)
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

    /// Deals a row: one card face up onto every column. Not while a column is empty.
    @discardableResult
    public mutating func draw() -> Bool {
        guard canDeal else { return false }
        for column in 0..<Self.tableauCount {
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
                  zip(run, run.dropFirst()).allSatisfy({ Self.continues($1, $0) }) else { continue }
            foundations[slot] = Array(run)
            tableau[column].removeLast(13)
        }
        for column in tableau.indices {
            if let last = tableau[column].indices.last { tableau[column][last].isFaceUp = true }
        }
    }
}

// MARK: - Hint

extension Spider {
    /// The best move; `.draw` when only the stock can help; `nil` when nothing helps.
    ///
    /// With a column empty, dealing is blocked, so the hint is to fill it (with a card that isn't the column's
    /// only one). That is the only time a hint puts a card into an empty column without uncovering something.
    public var hint: Hint? {
        if let move = usefulMoves.first { return .move(move) }
        if stock.isEmpty { return nil }
        if canDeal { return .draw }
        return fillingMove.map(Hint.move)
    }

    /// Moves that make progress, best first: one that completes a run; one that turns up a face-down card (onto
    /// the same suit first, then from the column with most hidden cards); one that puts a card on the same suit
    /// when it isn't already on it; and, once the stock is empty, a whole column onto another, which empties it.
    /// Every one of these strictly improves the position (fewer hidden cards, fewer cards, more same-suit pairs,
    /// fewer columns), so following the hint never goes in circles.
    public var usefulMoves: [Move] {
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        let runsBefore = foundations.filter { !$0.isEmpty }.count
        var candidates: [(move: Move, rank: Int, tiebreak: Int)] = []
        for column in columns {
            let cards = cards(in: column)
            for index in cards.indices where canPickUp(from: column, at: index) {
                let card = cards[index]
                let below = index > 0 ? cards[index - 1] : nil
                let uncovers = below.map { !$0.isFaceUp } ?? false
                let sameSuitBelow = below.map { $0.isFaceUp && Self.continues(card, $0) } ?? false
                for destination in columns where destination != column {
                    let move = Move(from: column, index: index, to: destination)
                    guard canApply(move) else { continue }
                    let target = self.cards(in: destination).last
                    var after = self
                    after.apply(move)
                    let completes = after.foundations.filter { !$0.isEmpty }.count > runsBefore
                    let onSameSuit = target?.suit == card.suit
                    let hidden = cards.prefix { !$0.isFaceUp }.count
                    if completes {
                        candidates.append((move, 0, 0))
                    } else if uncovers {
                        candidates.append((move, onSameSuit ? 1 : 2, -hidden))
                    } else if index == 0, target != nil {
                        // A whole column onto another empties it, and an empty column blocks the stock. So with
                        // cards in the stock only a move onto the same suit counts, and only when the empty
                        // column can then be filled without splitting a pair (else filling and rejoining loop).
                        if stock.isEmpty {
                            candidates.append((move, onSameSuit ? 3 : 4, 0))
                        } else if onSameSuit, after.fillingChoice.map({ !$0.breaksPair }) == true {
                            candidates.append((move, 3, index - cards.count))
                        }
                    } else if onSameSuit, !sameSuitBelow {
                        candidates.append((move, 3, index - cards.count))
                    }
                }
            }
        }
        return candidates.enumerated()
            .sorted { a, b in
                let (x, y) = (a.element, b.element)
                if x.rank != y.rank { return x.rank < y.rank }
                if x.tiebreak != y.tiebreak { return x.tiebreak < y.tiebreak }
                return a.offset < b.offset
            }
            .map(\.element.move)
    }

    /// The last card of a column with at least two cards, onto an empty column, so the stock can be dealt.
    private var fillingMove: Move? { fillingChoice?.move }

    /// The filling move, and whether it splits a same-suit pair. A card that doesn't split one is chosen first.
    private var fillingChoice: (move: Move, breaksPair: Bool)? {
        guard let empty = tableau.firstIndex(where: \.isEmpty) else { return nil }
        let sources = tableau.indices.filter { tableau[$0].count >= 2 && canPickUp(from: .tableau($0), at: tableau[$0].count - 1) }
        func breaksPair(_ column: Int) -> Bool {
            let cards = tableau[column]
            return Self.continues(cards[cards.count - 1], cards[cards.count - 2])
        }
        guard let column = sources.first(where: { !breaksPair($0) }) ?? sources.first else { return nil }
        return (Move(from: .tableau(column), index: tableau[column].count - 1, to: .tableau(empty)), breaksPair(column))
    }
}
