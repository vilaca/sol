/// FreeCell has no rule options yet. To add one, give it a stored property with its default value here
/// (and a row in the app's `FreeCell.ruleSettings`); saves from before decode it as that default.
public struct FreeCellOptions: GameOptions {
    public init() {}
}

/// FreeCell: every card dealt face up into eight columns, four free cells and four foundations.
public struct FreeCell: SolitaireGame {
    public static let kind = GameKind.freeCell
    public static let cellCount = 4
    public static let foundationCount = 4
    public static let tableauCount = 8

    /// Each free cell holds no card or one.
    public private(set) var cells: [[Card]]
    public private(set) var foundations: [[Card]]
    public private(set) var tableau: [[Card]]
    public let options: FreeCellOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: FreeCellOptions = FreeCellOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck.map { Card(suit: $0.suit, rank: $0.rank, isFaceUp: true) }
        deck.deterministicShuffle(using: &rng)
        // Dealt in turn across the columns: the first four get seven cards, the others six.
        var tableau = Array(repeating: [Card](), count: Self.tableauCount)
        for (i, card) in deck.enumerated() {
            tableau[i % Self.tableauCount].append(card)
        }
        self.init(
            cells: Array(repeating: [], count: Self.cellCount),
            foundations: Array(repeating: [], count: Self.foundationCount),
            tableau: tableau,
            options: options,
            seed: seed
        )
    }

    init(cells: [[Card]], foundations: [[Card]], tableau: [[Card]], options: FreeCellOptions = FreeCellOptions(), seed: UInt64 = 0) {
        self.cells = cells
        self.foundations = foundations
        self.tableau = tableau
        self.options = options
        self.seed = seed
    }

    /// How many cards can move together: one per free cell plus one, doubled for each empty column.
    /// The same rule serves every game with free cells (Eight Off).
    public static func maxMovableRun(freeCells: Int, emptyColumns: Int) -> Int {
        (freeCells + 1) << emptyColumns
    }

    /// Down by one in alternating colours, bottom to top.
    public static func isRun(_ cards: ArraySlice<Card>) -> Bool {
        zip(cards, cards.dropFirst()).allSatisfy { lower, upper in
            upper.rank == lower.rank - 1 && upper.suit.isRed != lower.suit.isRed
        }
    }

    /// Where the run on top of the column starts (0 for an empty column).
    static func topRunStart(_ cards: [Card]) -> Int {
        var start = max(0, cards.count - 1)
        while start > 0, isRun(cards[(start - 1)...start]) { start -= 1 }
        return start
    }

    // MARK: - Queries

    public var piles: [Pile] {
        (0..<Self.cellCount).map(Pile.cell) + (0..<Self.foundationCount).map(Pile.foundation)
            + (0..<Self.tableauCount).map(Pile.tableau)
    }

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock, .waste: []
        case .cell(let i): cells.indices.contains(i) ? cells[i] : []
        case .foundation(let i): foundations.indices.contains(i) ? foundations[i] : []
        case .tableau(let i): tableau.indices.contains(i) ? tableau[i] : []
        }
    }

    public var isWon: Bool {
        foundations.allSatisfy { $0.count == 13 }
    }

    /// Every column runs down in rank (in any suit), so the lowest card left can always go up next.
    public var canAutoComplete: Bool {
        !isWon && tableau.allSatisfy { column in zip(column, column.dropFirst()).allSatisfy { $0.rank >= $1.rank } }
    }

    /// A free-cell card, or a run in a column. Cards on the foundations stay there.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        let cards = cards(in: pile)
        guard cards.indices.contains(index) else { return false }
        switch pile {
        case .cell: return true
        case .tableau: return Self.isRun(cards[index...])
        default: return false
        }
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard source != destination, isValid(destination), canPickUp(from: source, at: index) else { return false }
        let sourceCards = cards(in: source)
        let card = sourceCards[index]
        let movingCount = sourceCards.count - index

        switch destination {
        case .foundation(let f):
            guard movingCount == 1 else { return false }
            return fits(card, on: foundations[f])
        case .cell(let c):
            return movingCount == 1 && cells[c].isEmpty
        case .tableau(let t):
            let emptyColumns = tableau.filter(\.isEmpty).count - (tableau[t].isEmpty ? 1 : 0)
            let freeCells = cells.filter(\.isEmpty).count
            guard movingCount <= Self.maxMovableRun(freeCells: freeCells, emptyColumns: emptyColumns) else { return false }
            guard let top = tableau[t].last else { return true }
            return card.rank == top.rank - 1 && card.suit.isRed != top.suit.isRed
        case .stock, .waste:
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

    /// The next card of some foundation.
    func fitsFoundation(_ card: Card) -> Bool {
        foundations.contains { fits(card, on: $0) }
    }

    private func isValid(_ pile: Pile) -> Bool {
        switch pile {
        case .stock, .waste: false
        case .cell(let i): cells.indices.contains(i)
        case .foundation(let i): foundations.indices.contains(i)
        case .tableau(let i): tableau.indices.contains(i)
        }
    }

    private mutating func set(_ cards: [Card], in pile: Pile) {
        switch pile {
        case .stock, .waste: break
        case .cell(let i): cells[i] = cards
        case .foundation(let i): foundations[i] = cards
        case .tableau(let i): tableau[i] = cards
        }
    }
}

// MARK: - Hint

extension FreeCell {
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move)
    }

    /// Moves that make progress, best first: foundation moves, then moves that free a card the foundations
    /// need or empty a column, then moves into free cells, then moves that tidy up. Splitting a run to move
    /// part of it onto a card like the one it sits on is left out: it is legal, but it never gets the game
    /// closer to a win. So with no useful move left, the game is stuck.
    public var usefulMoves: [Move] {
        var moves: [Move] = []
        func add(_ source: Pile, _ index: Int, to destination: Pile) {
            let move = Move(from: source, index: index, to: destination)
            if canApply(move), !moves.contains(move) { moves.append(move) }
        }
        let columns = (0..<Self.tableauCount).map(Pile.tableau)
        let filled = columns.filter { !cards(in: $0).isEmpty }
        let empty = columns.filter { cards(in: $0).isEmpty }
        let cellPiles = (0..<Self.cellCount).map(Pile.cell)
        // Columns with a card the foundations need under other cards, fewest cards on top of it first.
        let buried: [(column: Pile, index: Int)] = filled.compactMap { column in
            let cards = cards(in: column)
            guard let index = cards.dropLast().lastIndex(where: fitsFoundation) else { return nil }
            return (column, index)
        }
        .sorted { cards(in: $0.column).count - $0.index < cards(in: $1.column).count - $1.index }
        let burying = Set(buried.map(\.column))

        // 1. A card onto a foundation, lowest first.
        let tops = (cellPiles + filled).compactMap { pile in cards(in: pile).indices.last.map { (pile: pile, index: $0) } }
        for top in tops.sorted(by: { cards(in: $0.pile)[$0.index].rank < cards(in: $1.pile)[$1.index].rank }) {
            if let foundation = foundationDestination(from: top.pile, at: top.index) {
                add(top.pile, top.index, to: foundation)
            }
        }

        // 2. A whole column onto another that doesn't bury a needed card, which empties it; then the run
        // over a needed card off it.
        for column in filled where Self.topRunStart(cards(in: column)) == 0 {
            for destination in filled where destination != column && !burying.contains(destination) {
                add(column, 0, to: destination)
            }
        }
        for (column, index) in buried {
            let start = max(Self.topRunStart(cards(in: column)), index + 1)
            let destinations = start == index + 1 ? filled + empty : filled
            for destination in destinations where destination != column { add(column, start, to: destination) }
        }

        // 3. The top card over a needed card into a free cell.
        if let cell = cellPiles.first(where: { cards(in: $0).isEmpty }) {
            for (column, _) in buried { add(column, cards(in: column).count - 1, to: cell) }
        }

        // 4. A free-cell card back onto a column, unless that buries a needed card.
        for cell in cellPiles where !cards(in: cell).isEmpty {
            for destination in filled + empty where !burying.contains(destination) { add(cell, 0, to: destination) }
        }

        // 5. The run over a needed card into an empty column.
        for (column, index) in buried {
            let start = max(Self.topRunStart(cards(in: column)), index + 1)
            for destination in empty { add(column, start, to: destination) }
        }

        // 6. A run onto a card it continues, joining two runs.
        for column in filled {
            let start = Self.topRunStart(cards(in: column))
            guard start > 0 else { continue }
            for destination in filled where destination != column { add(column, start, to: destination) }
        }

        // 7. Last, a free-cell card onto a column even if that buries a needed card: it frees a cell.
        for cell in cellPiles where !cards(in: cell).isEmpty {
            for destination in filled { add(cell, 0, to: destination) }
        }
        return moves
    }
}
