public struct PyramidOptions: GameOptions {
    /// How many times the waste can be turned back over into the stock: 0 never, -1 always. Twice by default.
    public var recycles = 2
    public init() {}
}

/// Pyramid: a pyramid of seven rows (28 cards, all face up), a stock of 24 and a waste. Every position is a
/// `.tableau(i)` pile of zero or one card, numbered row by row from the top. A card is free once the two cards
/// of the row below that overlap it are gone. Two free cards (or a free card and the waste's top card) whose
/// ranks add up to 13 go to the foundation together, and a king goes alone. The stock turns one card onto the
/// waste; the waste can be recycled as many times as `options.recycles` says. Won when the pyramid is cleared.
///
/// A pair is the move "pick up A, drop it on B": `move(from: A, at: 0, to: B)`, where B is a `.tableau`
/// position or the `.waste`. A king moves to `.foundation(0)`.
public struct Pyramid: SolitaireGame {
    public static let kind = GameKind.pyramid
    public static let pairsCards = true
    public static let positionCount = 28
    public static let rowCount = 7

    public private(set) var stock: [Card]
    public private(set) var waste: [Card]
    public private(set) var tableau: [[Card]]
    /// Every card taken out of the pyramid or the waste.
    public private(set) var foundation: [Card]
    public let options: PyramidOptions
    public let seed: UInt64
    public private(set) var moveCount = 0
    /// How often the waste has been turned back over.
    public private(set) var recyclesUsed = 0

    public init(seed: UInt64, options: PyramidOptions = PyramidOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck
        deck.deterministicShuffle(using: &rng)
        var tableau: [[Card]] = []
        for _ in 0..<Self.positionCount {
            var card = deck.removeLast()
            card.isFaceUp = true
            tableau.append([card])
        }
        self.init(stock: deck, waste: [], tableau: tableau, options: options, seed: seed)
    }

    init(stock: [Card], waste: [Card], tableau: [[Card]], foundation: [Card] = [], options: PyramidOptions = PyramidOptions(), seed: UInt64 = 0) {
        self.stock = stock
        self.waste = waste
        self.tableau = tableau
        self.foundation = foundation
        self.options = options
        self.seed = seed
    }

    // MARK: - Layout

    /// The row of a position, 0 at the top.
    public static func row(of position: Int) -> Int {
        var row = 0
        while (row + 1) * (row + 2) / 2 <= position { row += 1 }
        return row
    }

    /// The place in its row, 0 at the left.
    public static func column(of position: Int) -> Int {
        position - row(of: position) * (row(of: position) + 1) / 2
    }

    /// Where a position sits: `x` in card widths from the left edge, `row` from the top. Each card sits
    /// between the two below it that overlap it.
    public static func coordinates(of position: Int) -> (x: Double, row: Int) {
        let row = row(of: position)
        return (Double(rowCount - 1 - row) / 2 + Double(column(of: position)), row)
    }

    /// The positions that overlap this one from the row below.
    static func coveringPositions(of position: Int) -> [Int] {
        let row = row(of: position)
        guard row < rowCount - 1 else { return [] }
        let below = (row + 1) * (row + 2) / 2 + column(of: position)
        return [below, below + 1]
    }

    // MARK: - Queries

    public var piles: [Pile] { [.stock, .waste, .foundation(0)] + (0..<Self.positionCount).map(Pile.tableau) }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: stock
        case .waste: waste
        case .foundation(let i): i == 0 ? foundation : []
        case .cell: []
        case .tableau(let i): tableau.indices.contains(i) ? tableau[i] : []
        }
    }

    public var isWon: Bool { tableau.allSatisfy { $0.isEmpty } }

    public var canAutoComplete: Bool { false }

    /// Whether the waste can be turned back over into the stock (once the stock is empty).
    public var canRecycleWaste: Bool {
        !waste.isEmpty && (options.recycles < 0 || recyclesUsed < options.recycles)
    }

    /// A card is free when it is there and nothing overlaps it any more.
    func isFree(_ position: Int) -> Bool {
        guard tableau.indices.contains(position), !tableau[position].isEmpty else { return false }
        return Self.coveringPositions(of: position).allSatisfy { tableau[$0].isEmpty }
    }

    /// Free cards of the pyramid, and the waste's top card.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        switch pile {
        case .tableau(let i): index == 0 && isFree(i)
        case .waste: !waste.isEmpty && index == waste.count - 1
        default: false
        }
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canPickUp(from: source, at: index), let card = cards(in: source).last else { return false }
        switch destination {
        case .foundation(let i):
            return i == 0 && card.rank == 13
        case .tableau(let j):
            guard source != destination, isFree(j) else { return false }
            return card.rank + tableau[j][0].rank == 13
        case .waste:
            guard source != .waste, let top = waste.last else { return false }
            return card.rank + top.rank == 13
        default:
            return false
        }
    }

    /// A tap sends a king away. Any other card needs a partner, which the player picks (see `pairsCards`).
    public func bestDestination(from source: Pile, at index: Int) -> Pile? {
        canMove(from: source, at: index, to: .foundation(0)) ? .foundation(0) : nil
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination) else { return false }
        var removed = [take(from: source)]
        if destination != .foundation(0) { removed.append(take(from: destination)) }
        foundation.append(contentsOf: removed)
        moveCount += 1
        return true
    }

    private mutating func take(from pile: Pile) -> Card {
        switch pile {
        case .waste: waste.removeLast()
        case .tableau(let i): tableau[i].removeLast()
        default: preconditionFailure("only the waste and the pyramid give up cards")
        }
    }

    /// Turns the next stock card onto the waste; with the stock empty, turns the waste over if the options
    /// still allow it.
    @discardableResult
    public mutating func draw() -> Bool {
        if var card = stock.popLast() {
            card.isFaceUp = true
            waste.append(card)
        } else if canRecycleWaste {
            stock = waste.reversed().map { card in
                var card = card
                card.isFaceUp = false
                return card
            }
            waste = []
            recyclesUsed += 1
        } else {
            return false
        }
        moveCount += 1
        return true
    }
}

// MARK: - Hint

extension Pyramid {
    /// The cards that can leave now: the free cards of the pyramid, then the waste's top card.
    private var available: [Pile] {
        tableau.indices.filter(isFree).map(Pile.tableau) + (waste.isEmpty ? [] : [.waste])
    }

    /// Every pair or king that can leave now, best first. A move that frees more of the pyramid goes first;
    /// then the one that gives up fewer other pairings (a 6 with two 7s to match shouldn't pick blindly);
    /// then the lower position.
    public var usefulMoves: [Move] {
        let cards = available
        func top(_ pile: Pile) -> Int { pile == .waste ? waste.count - 1 : 0 }
        var moves: [Move] = []
        for (n, source) in cards.enumerated() {
            let king = Move(from: source, index: top(source), to: .foundation(0))
            if canApply(king) { moves.append(king) }
            // A pair is listed once, picked up from the pyramid card (the waste is only ever the partner).
            guard source != .waste else { continue }
            for other in cards[(n + 1)...] {
                let pair = Move(from: source, index: 0, to: other)
                if canApply(pair) { moves.append(pair) }
            }
        }
        let freeBefore = tableau.indices.filter(isFree).count
        func freed(_ move: Move) -> Int {
            var after = self
            after.apply(move)
            return after.tableau.indices.filter(after.isFree).count - freeBefore
        }
        func given(_ move: Move) -> Int {
            // Other pairings of either card that this move uses up.
            guard move.to != .foundation(0) else { return 0 }
            return [move.from, move.to].reduce(0) { total, pile in
                guard let card = self.cards(in: pile).last else { return total }
                return total + cards.filter { $0 != move.from && $0 != move.to && (self.cards(in: $0).last?.rank ?? 0) + card.rank == 13 }.count
            }
        }
        return moves.enumerated()
            .map { (offset: $0.offset, move: $0.element, freed: freed($0.element), given: given($0.element)) }
            .sorted {
                if $0.freed != $1.freed { return $0.freed > $1.freed }
                if $0.given != $1.given { return $0.given < $1.given }
                return $0.offset < $1.offset
            }
            .map(\.move)
    }

    /// The best pair; `.draw` when none is left and the stock (or a recycle) can turn up another card.
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move) ?? (stock.isEmpty && !canRecycleWaste ? nil : .draw)
    }

    /// Stuck means no pair now, and none that drawing could still make: no card the stock (or a recycled
    /// waste) can bring up is a king or adds up to 13 with a free card.
    public var isStuck: Bool {
        guard !isWon, usefulMoves.isEmpty else { return false }
        let reachable = stock + (canRecycleWaste ? waste : [])
        let free = tableau.indices.filter(isFree).map { tableau[$0][0].rank }
        return !reachable.contains { card in card.rank == 13 || free.contains(13 - card.rank) }
    }
}
