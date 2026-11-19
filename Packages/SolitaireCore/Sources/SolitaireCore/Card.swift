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

    public init(suit: Suit, rank: Int, isFaceUp: Bool = false) {
        precondition((1...13).contains(rank), "rank must be 1...13")
        self.suit = suit
        self.rank = rank
        self.isFaceUp = isFaceUp
    }

    /// Stable across face-up / face-down changes, unique within a deck.
    public var id: Int { suit.rawValue * 13 + rank - 1 }

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
