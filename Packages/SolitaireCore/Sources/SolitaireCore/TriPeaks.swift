public struct TriPeaksOptions: GameOptions {
    /// Whether an ace and a king count as neighbours (the default, as in most TriPeaks rules).
    public var wrapsKingAndAce = true
    public init() {}
}

/// TriPeaks: three peaks of four rows (3 + 6 + 9 + 10 cards) that overlap, a stock of 23 and a waste that starts
/// with one card. Every position is a `.tableau(i)` pile of zero or one card, numbered row by row from the top.
/// A card is free once the cards overlapping it are gone; free cards are face up and go to the waste when they are
/// one rank above or below the waste's top card. The stock turns one card onto the waste, once through.
/// Won when every peak is cleared.
public struct TriPeaks: SolitaireGame {
    public static let kind = GameKind.triPeaks
    public static let recyclesWaste = false
    public static let positionCount = 28
    /// Positions in each row, from the top.
    static let rowSizes = [3, 6, 9, 10]
    private static let rowStarts = [0, 3, 9, 18]

    public private(set) var stock: [Card]
    public private(set) var waste: [Card]
    public private(set) var tableau: [[Card]]
    public let options: TriPeaksOptions
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: TriPeaksOptions = TriPeaksOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck
        deck.deterministicShuffle(using: &rng)
        var tableau: [[Card]] = []
        for position in 0..<Self.positionCount {
            var card = deck.removeLast()
            card.isFaceUp = position >= Self.rowStarts[3]
            tableau.append([card])
        }
        var first = deck.removeLast()
        first.isFaceUp = true
        self.init(stock: deck, waste: [first], tableau: tableau, options: options, seed: seed)
    }

    init(stock: [Card], waste: [Card], tableau: [[Card]], options: TriPeaksOptions = TriPeaksOptions(), seed: UInt64 = 0) {
        self.stock = stock
        self.waste = waste
        self.tableau = tableau
        self.options = options
        self.seed = seed
    }

    // MARK: - Layout

    /// The row of a position, 0 at the top.
    public static func row(of position: Int) -> Int {
        rowStarts.lastIndex { $0 <= position } ?? 0
    }

    /// The peak (0 to 2) a position belongs to. The three shared cards of the bottom row count for the left peak.
    public static func peak(of position: Int) -> Int {
        let row = row(of: position)
        let offset = position - rowStarts[row]
        return min(2, offset / (rowSizes[row] / 3))
    }

    /// Where a position sits: `x` in card widths from the left edge, `row` from the top. Each card sits
    /// between the two below it that overlap it.
    public static func coordinates(of position: Int) -> (x: Double, row: Int) {
        let row = row(of: position)
        let offset = position - rowStarts[row]
        let x: Double = switch row {
        case 0: 1.5 + 3 * Double(offset)
        case 1: 1 + Double(offset + offset / 2)
        case 2: 0.5 + Double(offset)
        default: Double(offset)
        }
        return (x, row)
    }

    /// The positions that overlap this one from the row below.
    static func coveringPositions(of position: Int) -> [Int] {
        let row = row(of: position)
        guard row < 3 else { return [] }
        let offset = position - rowStarts[row]
        let below = rowStarts[row + 1]
        switch row {
        case 0: return [below + 2 * offset, below + 2 * offset + 1]
        case 1: return [below + offset + offset / 2, below + offset + offset / 2 + 1]
        default: return [below + offset, below + offset + 1]
        }
    }

    // MARK: - Queries

    public var piles: [Pile] { [.stock, .waste] + (0..<Self.positionCount).map(Pile.tableau) }

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

    /// A card is free when it is there and nothing overlaps it any more.
    func isFree(_ position: Int) -> Bool {
        guard tableau.indices.contains(position), !tableau[position].isEmpty else { return false }
        return Self.coveringPositions(of: position).allSatisfy { tableau[$0].isEmpty }
    }

    /// Only free cards can be played; face-down cards that are still covered can't.
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        guard case .tableau(let i) = pile, index == 0, isFree(i) else { return false }
        return tableau[i][0].isFaceUp
    }

    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard destination == .waste, canPickUp(from: source, at: index), let top = waste.last,
              case .tableau(let i) = source else { return false }
        return WasteRule.fits(tableau[i][0], on: top, wraps: options.wrapsKingAndAce)
    }

    /// A tap sends a free card to the waste.
    public func bestDestination(from source: Pile, at index: Int) -> Pile? {
        canMove(from: source, at: index, to: .waste) ? .waste : nil
    }

    // MARK: - Actions

    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination), case .tableau(let i) = source else { return false }
        waste.append(tableau[i].removeLast())
        // Cards this one overlapped may now be free: they turn face up.
        for position in tableau.indices where Self.coveringPositions(of: position).contains(i) && isFree(position) {
            tableau[position][0].isFaceUp = true
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

extension TriPeaks {
    /// Plays that can be made now, best first: the one after which the most cards can still be cleared
    /// without drawing. Ties go to the play that turns up more cards, then to the lower position.
    public var usefulMoves: [Move] {
        let plays = tableau.indices.compactMap { position -> Move? in
            let move = Move(from: .tableau(position), index: 0, to: .waste)
            return canApply(move) ? move : nil
        }
        func score(_ move: Move) -> (chain: Int, revealed: Int) {
            var after = self
            after.apply(move)
            let revealed = after.tableau.filter { $0.first?.isFaceUp == true }.count - tableau.filter { $0.first?.isFaceUp == true }.count
            return (WasteRule.longestChain(from: after) { $0.plays() }, revealed)
        }
        return plays.enumerated()
            .map { (offset: $0.offset, move: $0.element, score: score($0.element)) }
            .sorted {
                if $0.score.chain != $1.score.chain { return $0.score.chain > $1.score.chain }
                if $0.score.revealed != $1.score.revealed { return $0.score.revealed > $1.score.revealed }
                return $0.offset < $1.offset
            }
            .map(\.move)
    }

    /// The best play; `.draw` when no card fits and the stock has one; `nil` when neither is left.
    public var hint: Hint? {
        usefulMoves.first.map(Hint.move) ?? (stock.isEmpty ? nil : .draw)
    }

    /// Stuck means no play and nothing left to draw: the peaks can't change any more.
    public var isStuck: Bool {
        !isWon && stock.isEmpty && !tableau.indices.contains { canMove(from: .tableau($0), at: 0, to: .waste) }
    }

    /// Every position one play away.
    private func plays() -> [TriPeaks] {
        tableau.indices.compactMap { position in
            var after = self
            return after.move(from: .tableau(position), at: 0, to: .waste) ? after : nil
        }
    }
}
