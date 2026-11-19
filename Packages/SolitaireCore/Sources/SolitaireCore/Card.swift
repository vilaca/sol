public enum Suit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs

    public var isRed: Bool { self == .hearts || self == .diamonds }

    public var symbol: String {
        switch self {
        case .spades: "♠"
        case .hearts: "♥"
        case .diamonds: "♦"
        case .clubs: "♣"
        }
    }
}

public struct Card: Hashable, Codable, Sendable, Identifiable {
    public let suit: Suit
    /// 1 (ace) through 13 (king).
    public let rank: Int
    public var isFaceUp: Bool
    /// Which deck the card comes from, for games played with two: 0 or 1.
    public let deck: Int

    public init(suit: Suit, rank: Int, isFaceUp: Bool = false, deck: Int = 0) {
        precondition((1...13).contains(rank), "rank must be 1...13")
        self.suit = suit
        self.rank = rank
        self.isFaceUp = isFaceUp
        self.deck = deck
    }

    /// Stable across face-up / face-down changes, unique across both decks.
    public var id: Int { deck * 52 + suit.rawValue * 13 + rank - 1 }

    private enum CodingKeys: String, CodingKey { case suit, rank, isFaceUp, deck }

    /// Saves from before two-deck games have no `deck`: those cards are deck 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rank = try container.decode(Int.self, forKey: .rank)
        guard (1...13).contains(rank) else {
            throw DecodingError.dataCorruptedError(forKey: .rank, in: container, debugDescription: "rank must be 1...13")
        }
        self.init(
            suit: try container.decode(Suit.self, forKey: .suit),
            rank: rank,
            isFaceUp: try container.decode(Bool.self, forKey: .isFaceUp),
            deck: try container.decodeIfPresent(Int.self, forKey: .deck) ?? 0
        )
    }

    /// Deck 0 is written without `deck`, so one-deck saves keep their old shape.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(suit, forKey: .suit)
        try container.encode(rank, forKey: .rank)
        try container.encode(isFaceUp, forKey: .isFaceUp)
        if deck != 0 { try container.encode(deck, forKey: .deck) }
    }

    public var rankLabel: String {
        switch rank {
        case 1: "A"
        case 11: "J"
        case 12: "Q"
        case 13: "K"
        default: String(rank)
        }
    }

    public static var fullDeck: [Card] {
        Suit.allCases.flatMap { suit in (1...13).map { Card(suit: suit, rank: $0) } }
    }
}
