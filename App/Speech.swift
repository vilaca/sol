import SolitaireCore
import UIKit

extension Card {
    /// "Queen of hearts", in the app's language.
    var spokenName: String {
        let rankName = switch rank {
        case 1: String(localized: "Ace")
        case 11: String(localized: "Jack")
        case 12: String(localized: "Queen")
        case 13: String(localized: "King")
        default: String(rank)
        }
        return String(localized: "\(rankName) of \(suit.spokenName)", comment: "Card name: rank, then suit, e.g. Queen of hearts")
    }
}

extension Suit {
    var spokenName: String {
        switch self {
        case .spades: String(localized: "spades")
        case .hearts: String(localized: "hearts")
        case .diamonds: String(localized: "diamonds")
        case .clubs: String(localized: "clubs")
        }
    }
}

/// A move VoiceOver offers as a custom action on a card.
struct AccessibleMove: Equatable {
    let name: String
    let destination: Pile
}

/// Everything VoiceOver says about the board. Pure functions of the game, so they are unit-tested.
enum Speech {
    /// 1-based column number, as players count them.
    static func columnName(_ index: Int) -> String {
        String(localized: "Column \(index + 1)")
    }

    static func cellName(_ index: Int) -> String {
        String(localized: "Free cell \(index + 1)")
    }

    /// "Column 3", "Free cell 2", "Foundation": the default for `PlayableGame.spokenName(of:)`.
    static func pileName(_ pile: Pile) -> String {
        switch pile {
        case .tableau(let column): columnName(column)
        case .cell(let cell): cellName(cell)
        case .foundation: String(localized: "Foundation")
        case .waste: String(localized: "Waste")
        case .stock: String(localized: "Stock")
        }
    }

    /// The label of a card VoiceOver can focus, e.g. "Column 3, Queen of hearts, 4 hidden cards".
    static func label(for card: Card, in pile: Pile, at index: Int, of game: some PlayableGame) -> String {
        switch pile {
        case .stock:
            return stockLabel(game)
        case .waste:
            return String(localized: "Waste, \(card.spokenName)")
        case .foundation:
            return String(localized: "Foundation, \(card.spokenName)")
        case .cell:
            return [game.spokenName(of: pile), card.spokenName].joined(separator: separator)
        case .tableau:
            var parts = [game.spokenName(of: pile), card.spokenName]
            let cards = game.cards(in: pile)
            let hidden = cards.prefix { !$0.isFaceUp }.count
            if index == hidden, hidden > 0 {
                parts.append(String(localized: "\(hidden) hidden cards"))
            }
            let above = cards.count - 1 - index
            if above > 0 {
                parts.append(String(localized: "under \(above) cards"))
            }
            return parts.joined(separator: separator)
        }
    }

    static func stockLabel(_ game: some SolitaireGame) -> String {
        let stock = game.cards(in: .stock)
        return if !stock.isEmpty {
            String(localized: "Draw card, \(stock.count) left")
        } else if !game.cards(in: .waste).isEmpty {
            String(localized: "Turn the waste over")
        } else {
            String(localized: "Stock empty")
        }
    }

    /// What VoiceOver says for an empty pile's outline.
    static func emptyLabel(_ pile: Pile, of game: some PlayableGame) -> String {
        switch pile {
        case .stock: stockLabel(game)
        case .foundation: String(localized: "Empty foundation")
        default: String(localized: "\(game.spokenName(of: pile)), empty")
        }
    }

    /// Legal moves for the card at `index`: one foundation action and one free-cell action (if any), then each
    /// column it fits.
    static func moves(from pile: Pile, at index: Int, in game: some PlayableGame) -> [AccessibleMove] {
        var result: [AccessibleMove] = []
        if let foundation = game.foundationDestination(from: pile, at: index) {
            result.append(AccessibleMove(name: String(localized: "Move to foundation"), destination: foundation))
        }
        if !pile.isCell, let cell = game.piles.first(where: { $0.isCell && game.canMove(from: pile, at: index, to: $0) }) {
            result.append(AccessibleMove(name: String(localized: "Move to \(game.spokenName(of: cell))"), destination: cell))
        }
        for column in game.piles where column.isTableau && game.canMove(from: pile, at: index, to: column) {
            result.append(AccessibleMove(name: String(localized: "Move to \(game.spokenName(of: column))"), destination: column))
        }
        return result
    }

    /// What VoiceOver says after a move, e.g. "7 of clubs moved to column 5, revealed Queen of hearts".
    static func moved(_ card: Card, to destination: Pile, before: some PlayableGame, after: some PlayableGame, from source: Pile) -> String {
        var text = String(localized: "\(card.spokenName) moved to \(place(destination, in: after))")
        let remaining = after.cards(in: source)
        if case .tableau = source, let top = remaining.last, !before.cards(in: source)[remaining.count - 1].isFaceUp {
            text += separator + String(localized: "revealed \(top.spokenName)")
        }
        return text
    }

    /// "column 5", "free cell 2" or "foundation", as the end of "moved to …".
    private static func place(_ pile: Pile, in game: some PlayableGame) -> String {
        switch pile {
        case .tableau, .cell: game.spokenName(of: pile)
        default: String(localized: "foundation")
        }
    }

    static func drew(_ game: some SolitaireGame) -> String {
        if let top = game.cards(in: .waste).last {
            String(localized: "Drew \(top.spokenName)")
        } else {
            String(localized: "Waste turned over")
        }
    }

    /// "Hint: move 7 of clubs to column 5", or "No moves left".
    static func hint(_ hint: Hint?, in game: some PlayableGame) -> String {
        switch hint {
        case .move(let move):
            let card = game.cards(in: move.from)[move.index]
            return String(localized: "Hint: move \(card.spokenName) to \(place(move.to, in: game))")
        case .draw:
            return game.cards(in: .stock).isEmpty ? String(localized: "Hint: turn the waste over") : String(localized: "Hint: draw a card")
        case nil:
            return noMovesLeft
        }
    }

    private static var separator: String {
        String(localized: ", ", comment: "Separates the parts of a spoken card label")
    }

    static var noMovesLeft: String { String(localized: "No moves left") }
    static var notAllowed: String { String(localized: "Not allowed") }
    static var won: String { String(localized: "You won!") }

    @MainActor
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
