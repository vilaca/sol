import Foundation

/// Every game Sol offers. The raw value names the game in saves and statistics keys: never change it.
public enum GameKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case klondike
    case freeCell = "freecell"

    public var id: String { rawValue }
}

public enum Pile: Hashable, Codable, Sendable {
    case stock
    case waste
    case foundation(Int)
    case tableau(Int)
    /// A free cell, which holds one card (FreeCell and its family).
    case cell(Int)
}

extension Pile {
    public var isFoundation: Bool {
        if case .foundation = self { return true }
        return false
    }

    public var isTableau: Bool {
        if case .tableau = self { return true }
        return false
    }

    public var isCell: Bool {
        if case .cell = self { return true }
        return false
    }
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

/// A game's rule options: a small value dealt into each game and saved with it. `init()` gives the defaults.
/// Options added later decode as their defaults from older saves (see `decodeSaved(from:)`).
public protocol GameOptions: Codable, Equatable, Sendable {
    init()
}

/// The rules and state of one solitaire game. A value type, so undo is just keeping old copies.
///
/// Implement the requirements without a default; the others have one (below) that suits most games.
public protocol SolitaireGame: Codable, Equatable, Sendable {
    associatedtype Options: GameOptions

    static var kind: GameKind { get }

    /// A new deal. The same seed and options always give the same deal.
    init(seed: UInt64, options: Options)

    /// The rules this game was dealt with.
    var options: Options { get }
    var seed: UInt64 { get }
    var moveCount: Int { get }

    /// Every pile of the board, stock and waste first, then foundations, then the rest.
    var piles: [Pile] { get }
    /// The cards of a pile; the last is the top card.
    func cards(in pile: Pile) -> [Card]
    var isWon: Bool { get }

    /// Whether the player can pick up this card (with the cards on top of it) to drag or tap it.
    /// Default: a face-up card in a column, or the top card of any other pile.
    func canPickUp(from pile: Pile, at index: Int) -> Bool
    func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool
    /// Moves the card at `index` and every card above it. Returns `false`, changing nothing, when not allowed.
    mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool

    /// The foundation this card can go to, if any.
    func foundationDestination(from source: Pile, at index: Int) -> Pile?
    /// Where a tap on this card sends it. Default: a foundation, then a non-empty column, then a free cell,
    /// then an empty column.
    func bestDestination(from source: Pile, at index: Int) -> Pile?

    /// Nothing is left to find out: the app offers Finish, which plays `nextAutoMove()` until the game is won.
    var canAutoComplete: Bool { get }
    /// The next card that can go to a foundation, lowest rank first.
    func nextAutoMove() -> Move?

    /// A tap on the stock. Default: nothing (games without a stock).
    mutating func draw() -> Bool

    /// The most useful move, `.draw` when only the stock can help, or `nil` when nothing helps.
    var hint: Hint? { get }
    /// The game can't be won from here, so the app offers to undo or deal again. Default: no hint.
    var isStuck: Bool { get }
}

extension SolitaireGame {
    public func canPickUp(from pile: Pile, at index: Int) -> Bool {
        let cards = cards(in: pile)
        guard cards.indices.contains(index), cards[index].isFaceUp else { return false }
        return pile.isTableau || index == cards.count - 1
    }

    public func canApply(_ move: Move) -> Bool {
        canMove(from: move.from, at: move.index, to: move.to)
    }

    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        self.move(from: move.from, at: move.index, to: move.to)
    }

    public func foundationDestination(from source: Pile, at index: Int) -> Pile? {
        piles.first { $0.isFoundation && canMove(from: source, at: index, to: $0) }
    }

    public func bestDestination(from source: Pile, at index: Int) -> Pile? {
        if !source.isFoundation, let foundation = foundationDestination(from: source, at: index) {
            return foundation
        }
        let columns = piles.filter(\.isTableau)
        if let column = columns.first(where: { !cards(in: $0).isEmpty && canMove(from: source, at: index, to: $0) }) {
            return column
        }
        if !source.isCell, let cell = piles.first(where: { $0.isCell && canMove(from: source, at: index, to: $0) }) {
            return cell
        }
        // A card already at the bottom of a column gains nothing from moving to another empty column.
        if source.isTableau, index == 0 { return nil }
        return columns.first { cards(in: $0).isEmpty && canMove(from: source, at: index, to: $0) }
    }

    public func nextAutoMove() -> Move? {
        let candidates = piles
            .filter { $0 != .stock && !$0.isFoundation && !cards(in: $0).isEmpty }
            .map { Move(from: $0, index: cards(in: $0).count - 1, to: $0) }
        let sorted = candidates.sorted { cards(in: $0.from)[$0.index].rank < cards(in: $1.from)[$1.index].rank }
        for candidate in sorted {
            if let foundation = foundationDestination(from: candidate.from, at: candidate.index) {
                return Move(from: candidate.from, index: candidate.index, to: foundation)
            }
        }
        return nil
    }

    public mutating func draw() -> Bool { false }

    public var isStuck: Bool { !isWon && hint == nil }

    /// Which pile each card is in, keyed by `Card.id`.
    public var pileByCard: [Int: Pile] {
        var result: [Int: Pile] = [:]
        for pile in piles {
            for card in cards(in: pile) { result[card.id] = pile }
        }
        return result
    }

    /// Equality across game types, for code that holds `any SolitaireGame`.
    public func isEqual(to other: any SolitaireGame) -> Bool {
        (other as? Self) == self
    }

    /// Decodes a saved game. Its options are read over the defaults, so an option added since the save
    /// takes its default value instead of failing the whole save.
    public static func decodeSaved(from data: Data) throws -> Self {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return try JSONDecoder().decode(Self.self, from: data)
        }
        object["options"] = try Options.merged(object["options"])
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

extension GameOptions {
    /// Decodes saved options; settings missing from them take their default values.
    public static func decodeSaved(from data: Data) throws -> Self {
        let merged = try merged(JSONSerialization.jsonObject(with: data))
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    /// The defaults as a JSON object, overwritten by whatever `saved` holds.
    fileprivate static func merged(_ saved: Any?) throws -> [String: Any] {
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self())) as? [String: Any] ?? [:]
        return defaults.merging(saved as? [String: Any] ?? [:]) { _, saved in saved }
    }
}
