import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }

private func golf(
    waste: [Card], columns: [[Card]], stock: [Card] = [], options: GolfOptions = GolfOptions()
) -> Golf {
    Golf(stock: stock, waste: waste, tableau: columns + Array(repeating: [], count: 7 - columns.count), options: options)
}

@Suite struct GolfDealTests {
    @Test func dealsSevenColumnsOfFiveFaceUpAndSixteenInTheStock() {
        let game = Golf(seed: 42)
        #expect(game.tableau.map(\.count) == Array(repeating: 5, count: 7))
        #expect(game.tableau.allSatisfy { $0.allSatisfy { $0.isFaceUp } })
        #expect(game.waste.count == 1 && game.waste[0].isFaceUp)
        #expect(game.stock.count == 16)
        #expect(game.stock.allSatisfy { !$0.isFaceUp })
        let ids = (game.tableau.flatMap { $0 } + game.waste + game.stock).map(\.id)
        #expect(Set(ids).count == 52)
        #expect(game.moveCount == 0)
        #expect(!game.options.wrapsKingAndAce)
    }

    @Test func sameSeedSameDeal() {
        #expect(Golf(seed: 5) == Golf(seed: 5))
        #expect(Golf(seed: 5).tableau != Golf(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(Golf(seed: seed).hint != nil)
            #expect(!Golf(seed: seed).isStuck)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = Golf(seed: .max)
        game.draw()
        let decoded = try Golf.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }

    @Test func saveWithoutOptionsDecodesWithTheDefaults() throws {
        let game = Golf(seed: 3)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        object["options"] = nil
        let decoded = try Golf.decodeSaved(from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == game)
    }
}

@Suite struct GolfMoveTests {
    @Test func playsOneRankAboveOrBelowTheWaste() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 6)], [up(.clubs, 8)], [up(.clubs, 9)], [up(.clubs, 7)]])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .waste))
        #expect(game.canMove(from: .tableau(1), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .waste), "two ranks away")
        #expect(!game.canMove(from: .tableau(3), at: 0, to: .waste), "same rank")
    }

    @Test func onlyTheTopCardOfAColumnPlays() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 6), up(.clubs, 2)]])
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .waste))
        #expect(!game.canPickUp(from: .tableau(0), at: 0))
        #expect(game.canPickUp(from: .tableau(0), at: 1))
        #expect(!game.canPickUp(from: .waste, at: 0))
    }

    @Test func movePutsTheCardOnTheWaste() {
        var game = golf(waste: [up(.hearts, 7)], columns: [[up(.clubs, 2), up(.spades, 6)]])
        let moved = game.move(from: .tableau(0), at: 1, to: .waste)
        #expect(moved)
        #expect(game.waste.map(\.rank) == [7, 6])
        #expect(game.tableau[0].map(\.rank) == [2])
        #expect(game.moveCount == 1)
    }

    @Test func illegalMoveChangesNothing() {
        var game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 2)]])
        let before = game
        let moved = game.move(from: .tableau(0), at: 0, to: .waste)
        #expect(!moved)
        #expect(game == before)
        let toColumn = game.move(from: .tableau(0), at: 0, to: .tableau(1))
        #expect(!toColumn)
        #expect(game == before)
    }

    @Test func badPileIndexesDoNotTrap() {
        let game = Golf(seed: 1)
        #expect(!game.canMove(from: .tableau(99), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(-1), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(0), at: 99, to: .waste))
        #expect(game.cards(in: .tableau(99)).isEmpty)
        #expect(game.cards(in: .foundation(0)).isEmpty)
    }

    @Test func tapSendsTheTopCardToTheWaste() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 6)], [up(.spades, 2)]])
        #expect(game.bestDestination(from: .tableau(0), at: 0) == .waste)
        #expect(game.bestDestination(from: .tableau(1), at: 0) == nil)
    }

    @Test func drawTurnsTheNextCardOntoTheWasteAndNeverRedeals() {
        var game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 2)]], stock: [Card(suit: .clubs, rank: 3), Card(suit: .clubs, rank: 4)])
        let first = game.draw()
        #expect(first)
        #expect(game.waste.last == up(.clubs, 4))
        #expect(game.stock.count == 1)
        let second = game.draw()
        #expect(second)
        let third = game.draw()
        #expect(!third, "no redeal")
        #expect(game.waste.count == 3 && game.stock.isEmpty)
        #expect(game.moveCount == 2)
        #expect(!Golf.recyclesWaste)
    }

    @Test func winsWhenEveryColumnIsEmpty() {
        var game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 6)]])
        #expect(!game.isWon)
        game.move(from: .tableau(0), at: 0, to: .waste)
        #expect(game.isWon)
        #expect(!game.isStuck)
    }
}

@Suite struct GolfOptionTests {
    @Test func noWrapByDefault() {
        let game = golf(waste: [up(.hearts, 1)], columns: [[up(.spades, 13)]])
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .waste))
        let other = golf(waste: [up(.hearts, 13)], columns: [[up(.spades, 1)]])
        #expect(!other.canMove(from: .tableau(0), at: 0, to: .waste))
    }

    @Test func wrapLetsAKingGoOnAnAceAndBack() {
        var options = GolfOptions()
        options.wrapsKingAndAce = true
        let onAce = golf(waste: [up(.hearts, 1)], columns: [[up(.spades, 13)]], options: options)
        #expect(onAce.canMove(from: .tableau(0), at: 0, to: .waste))
        let onKing = golf(waste: [up(.hearts, 13)], columns: [[up(.spades, 1)]], options: options)
        #expect(onKing.canMove(from: .tableau(0), at: 0, to: .waste))
        let far = golf(waste: [up(.hearts, 13)], columns: [[up(.spades, 2)]], options: options)
        #expect(!far.canMove(from: .tableau(0), at: 0, to: .waste))
    }

    @Test func aGameKeepsTheRulesItWasDealtWith() {
        var options = GolfOptions()
        options.wrapsKingAndAce = true
        #expect(Golf(seed: 1, options: options).options.wrapsKingAndAce)
    }
}

@Suite struct GolfHintTests {
    @Test func prefersThePlayThatClearsTheMostCards() {
        // Column 0's 8 leads nowhere; column 1's 6 is followed by its 5, then the 4 under it.
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.clubs, 2), up(.spades, 8)], [up(.clubs, 4), up(.clubs, 5), up(.spades, 6)]])
        #expect(game.hint == .move(Move(from: .tableau(1), index: 2, to: .waste)))
        #expect(game.usefulMoves.count == 2)
    }

    @Test func movesComeBeforeDrawing() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 6)]], stock: [Card(suit: .clubs, rank: 3)])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 0, to: .waste)))
    }

    @Test func drawsWhenNoCardFits() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 2)]], stock: [Card(suit: .clubs, rank: 3)])
        #expect(game.hint == .draw)
        #expect(!game.isStuck)
    }

    @Test func stuckWhenNothingFitsAndTheStockIsEmpty() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 2)]])
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func notStuckWhenAPlayRemainsWithAnEmptyStock() {
        let game = golf(waste: [up(.hearts, 7)], columns: [[up(.spades, 6)]])
        #expect(!game.isStuck)
    }

    @Test func followingTheHintNeverLoops() {
        for seed in UInt64(0)..<20 {
            var game = Golf(seed: seed)
            var steps = 0
            while let hint = game.hint, steps < 200 {
                switch hint {
                case .move(let move): game.apply(move)
                case .draw: game.draw()
                }
                steps += 1
            }
            #expect(steps < 200)
            #expect(game.isWon || game.isStuck)
        }
    }
}
