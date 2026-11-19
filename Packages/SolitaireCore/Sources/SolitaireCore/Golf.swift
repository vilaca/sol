public struct GolfOptions: GameOptions {
    /// Whether an ace and a king count as neighbours (a king can go on an ace and the other way round).
    public var wrapsKingAndAce = false
    public init() {}
}

/// Golf: seven columns of five, all face up, a stock of 16 and a waste that starts with one card. The top card
/// of a column goes to the waste when it is one rank above or below the waste's top card. The stock turns one
/// card onto the waste, once through. Won when every column is empty.
public struct Golf: SolitaireGame {
    public static let kind = GameKind.golf
    public static let recyclesWaste = false
    public static let tableauCount = 7

    public private(set) var stock: [Card]
    public private(set) var waste: [Card]
    public private(set) var tableau: [[Card]]
    public let options: GolfOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: GolfOptions = GolfOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck
        deck.deterministicShuffle(using: &rng)
        for i in deck.indices { deck[i].isFaceUp = true }
        var tableau: [[Card]] = []
        for _ in 0..<Self.tableauCount {
            tableau.append(Array(deck.suffix(5)))
            deck.removeLast(5)
        }
        let waste = [deck.removeLast()]
        for i in deck.indices { deck[i].isFaceUp = false }
        self.init(stock: deck, waste: waste, tableau: tableau, options: options, seed: seed)
    }

    init(stock: [Card], waste: [Card], tableau: [[Card]], options: GolfOptions = GolfOptions(), seed: UInt64 = 0) {
        self.stock = stock
        self.waste = waste
        self.tableau = tableau
        self.options = options
        self.seed = seed
    }

    // MARK: - Queries

    public var piles: [Pile] { [.stock, .waste] + (0..<Self.tableauCount).map(Pile.tableau) }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: stock
        case .waste: waste
        case .foundation, .cell: []
        case .tableau(let i): tableau.indices.contains(i) ? tableau[i] : []
        }
    }

    public var isWon: Bool { tableau.allSatisfy { $0.isEmpty } }

    public var canAutoComplete: Bool { false }

    /// Only the top card of a column can be played.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        guard case .tableau(let i) = pile, tableau.indices.contains(i) else { return false }
        return index == tableau[i].count - 1 && index >= 0
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard destination == .waste, canPickUp(from: source, at: index), let top = waste.last,
              case .tableau(let i) = source else { return false }
        return WasteRule.fits(tableau[i][index], on: top, wraps: options.wrapsKingAndAce)
    }

    /// A tap sends a column's top card to the waste.
    public func bestDestination(from source: Pile, at index: Int) -> Pile? {
        canMove(from: source, at: index, to: .waste) ? .waste : nil
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination), case .tableau(let i) = source else { return false }
        waste.append(tableau[i].removeLast())
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

extension Golf {
    /// Plays that can be made now, best first: the one after which the most cards can still be cleared
    /// without drawing (ties keep column order).
    public var usefulMoves: [Move] {
        let plays = (0..<Self.tableauCount).compactMap { column -> Move? in
            let move = Move(from: .tableau(column), index: tableau[column].count - 1, to: .waste)
            return canApply(move) ? move : nil
        }
        func score(_ move: Move) -> Int {
            var after = self
            after.apply(move)
            return WasteRule.longestChain(from: after) { $0.plays() }
        }
        return plays.enumerated()
            .map { (offset: $0.offset, move: $0.element, score: score($0.element)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map(\.move)
    }

    /// The best play; `.draw` when no card fits and the stock has one; `nil` when neither is left.
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move) ?? (stock.isEmpty ? nil : .draw)
    }

    /// Stuck means no play and nothing left to draw: the layout can't change any more.
    public var isStuck: Bool {
        !isWon && stock.isEmpty && !hasPlay
    }

    private var hasPlay: Bool {
        (0..<Self.tableauCount).contains { canMove(from: .tableau($0), at: tableau[$0].count - 1, to: .waste) }
    }

    /// Every position one play away.
    private func plays() -> [Golf] {
        (0..<Self.tableauCount).compactMap { column in
            var after = self
            return after.move(from: .tableau(column), at: tableau[column].count - 1, to: .waste) ? after : nil
        }
    }
}
