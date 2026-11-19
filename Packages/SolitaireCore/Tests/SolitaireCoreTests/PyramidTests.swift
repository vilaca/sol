import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank) }

/// A position with only the given cards in the pyramid.
private func pyramid(
    cards: [Int: Card], waste: [Card] = [], stock: [Card] = [], options: PyramidOptions = PyramidOptions(), recycles: Int? = nil
) -> Pyramid {
    var options = options
    if let recycles { options.recycles = recycles }
    return Pyramid(stock: stock, waste: waste, tableau: (0..<28).map { cards[$0].map { [$0] } ?? [] }, options: options)
}

@Suite struct PyramidDealTests {
    @Test func dealsSevenRowsFaceUp() {
        let game = Pyramid(seed: 42)
        #expect(game.tableau.count == 28 && game.tableau.allSatisfy { $0.count == 1 && $0[0].isFaceUp })
        #expect(game.stock.count == 24 && game.stock.allSatisfy { !$0.isFaceUp })
        #expect(game.waste.isEmpty && game.foundation.isEmpty)
        let ids = (game.tableau.flatMap { $0 } + game.stock).map(\.id)
        #expect(Set(ids).count == 52)
        #expect(game.options.recycles == 2)
    }

    @Test func sameSeedSameDeal() {
        #expect(Pyramid(seed: 5) == Pyramid(seed: 5))
        #expect(Pyramid(seed: 5).tableau != Pyramid(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(Pyramid(seed: seed).hint != nil)
            #expect(!Pyramid(seed: seed).isStuck)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = Pyramid(seed: .max)
        game.draw()
        let decoded = try Pyramid.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }

    @Test func rowsColumnsAndCoveringPositions() {
        #expect([0, 1, 2, 3, 5, 6, 20, 21, 27].map(Pyramid.row(of:)) == [0, 1, 1, 2, 2, 3, 5, 6, 6])
        #expect([0, 1, 2, 3, 5, 21, 27].map(Pyramid.column(of:)) == [0, 0, 1, 0, 2, 0, 6])
        #expect(Pyramid.coveringPositions(of: 0) == [1, 2])
        #expect(Pyramid.coveringPositions(of: 2) == [4, 5])
        #expect(Pyramid.coveringPositions(of: 20) == [26, 27])
        #expect((21..<28).allSatisfy { Pyramid.coveringPositions(of: $0).isEmpty })
        for position in 0..<21 {
            let covering = Pyramid.coveringPositions(of: position)
            let middle = covering.map { Pyramid.coordinates(of: $0).x }.reduce(0, +) / 2
            #expect(Pyramid.coordinates(of: position).x == middle, "position \(position)")
        }
    }
}

@Suite struct PyramidMoveTests {
    @Test func onlyUncoveredCardsCanBePickedUp() {
        let game = Pyramid(seed: 42)
        for position in 0..<21 { #expect(!game.canPickUp(from: .tableau(position), at: 0)) }
        for position in 21..<28 { #expect(game.canPickUp(from: .tableau(position), at: 0)) }
        #expect(!game.canPickUp(from: .stock, at: 0))
        #expect(!game.canPickUp(from: .foundation(0), at: 0))
    }

    @Test func twoFreeCardsAddingTo13GoToTheFoundation() {
        var game = pyramid(cards: [21: up(.spades, 6), 22: up(.hearts, 7), 23: up(.clubs, 5)])
        #expect(game.canMove(from: .tableau(21), at: 0, to: .tableau(22)))
        #expect(game.canMove(from: .tableau(22), at: 0, to: .tableau(21)))
        #expect(!game.canMove(from: .tableau(21), at: 0, to: .tableau(23)))
        let paired = game.move(from: .tableau(21), at: 0, to: .tableau(22))
        #expect(paired)
        #expect(game.tableau[21].isEmpty && game.tableau[22].isEmpty && !game.tableau[23].isEmpty)
        #expect(game.foundation.count == 2 && game.moveCount == 1)
    }

    @Test func aCoveredCardCannotPair() {
        let game = pyramid(cards: [10: up(.spades, 6), 15: up(.hearts, 7), 16: up(.clubs, 2), 21: up(.clubs, 7)])
        #expect(!game.canMove(from: .tableau(10), at: 0, to: .tableau(21)))
        #expect(!game.canMove(from: .tableau(21), at: 0, to: .tableau(10)))
    }

    @Test func aKingGoesAlone() {
        var game = pyramid(cards: [21: up(.spades, 13), 22: up(.hearts, 13)])
        #expect(game.bestDestination(from: .tableau(21), at: 0) == .foundation(0))
        #expect(!game.canMove(from: .tableau(21), at: 0, to: .tableau(22)))
        let moved = game.move(from: .tableau(21), at: 0, to: .foundation(0))
        #expect(moved)
        #expect(game.tableau[21].isEmpty && !game.tableau[22].isEmpty && game.foundation.count == 1)
    }

    @Test func onlyAKingGoesToTheFoundationAlone() {
        var game = pyramid(cards: [21: up(.spades, 12)])
        let before = game
        let queen = game.move(from: .tableau(21), at: 0, to: .foundation(0))
        #expect(!queen)
        #expect(game.bestDestination(from: .tableau(21), at: 0) == nil)
        #expect(game == before)
    }

    @Test func theWasteTopPairsWithAFreeCardEitherWay() {
        let game = pyramid(cards: [21: up(.spades, 9)], waste: [up(.clubs, 2), up(.hearts, 4)])
        #expect(game.canMove(from: .waste, at: 1, to: .tableau(21)))
        #expect(game.canMove(from: .tableau(21), at: 0, to: .waste))
        var paired = game
        let moved = paired.move(from: .tableau(21), at: 0, to: .waste)
        #expect(moved)
        #expect(paired.waste.map(\.rank) == [2] && paired.tableau[21].isEmpty)
        #expect(!game.canMove(from: .waste, at: 0, to: .tableau(21)), "only the top card of the waste")
    }

    @Test func aKingOnTheWasteGoesAlone() {
        var game = pyramid(cards: [21: up(.spades, 2)], waste: [up(.hearts, 13)])
        #expect(game.bestDestination(from: .waste, at: 0) == .foundation(0))
        let moved = game.move(from: .waste, at: 0, to: .foundation(0))
        #expect(moved)
        #expect(game.waste.isEmpty)
    }

    @Test func clearingTwoCardsFreesTheOneTheyCovered() {
        var game = pyramid(cards: [15: up(.hearts, 3), 21: up(.spades, 6), 22: up(.hearts, 7), 16: up(.clubs, 9)])
        #expect(!game.isFree(15))
        #expect(game.isFree(16) == false)
        game.move(from: .tableau(21), at: 0, to: .tableau(22))
        #expect(game.isFree(15), "position 15 sits on 21 and 22")
    }

    @Test func illegalMovesChangeNothingAndBadPilesDoNotTrap() {
        var game = pyramid(cards: [21: up(.spades, 2), 22: up(.hearts, 3)], waste: [up(.clubs, 5)])
        let before = game
        for destination in [Pile.tableau(22), .tableau(99), .tableau(-1), .stock, .cell(0), .foundation(3), .waste] {
            let moved = game.move(from: .tableau(21), at: 0, to: destination)
            #expect(!moved)
        }
        let nowhere = game.move(from: .tableau(99), at: 0, to: .tableau(21))
        #expect(!nowhere)
        #expect(game.cards(in: .tableau(99)).isEmpty && game.cards(in: .foundation(1)).isEmpty)
        #expect(game == before)
    }

    @Test func winWhenThePyramidIsCleared() {
        var game = pyramid(cards: [27: up(.spades, 13)], stock: [down(.clubs, 4)])
        #expect(!game.isWon)
        game.move(from: .tableau(27), at: 0, to: .foundation(0))
        #expect(game.isWon)
        #expect(!game.isStuck)
    }
}

@Suite struct PyramidStockTests {
    @Test func drawTurnsOneCardOntoTheWaste() {
        var game = Pyramid(seed: 1)
        let next = game.stock.last!
        let drew = game.draw()
        #expect(drew)
        #expect(game.waste.count == 1 && game.waste[0].id == next.id && game.waste[0].isFaceUp && game.stock.count == 23)
        #expect(game.moveCount == 1)
    }

    @Test func recyclesTwiceByDefault() {
        var game = Pyramid(stock: [down(.clubs, 4)], waste: [], tableau: Array(repeating: [], count: 28))
        game.draw()
        let first = game.draw()
        #expect(first && game.stock.count == 1 && game.waste.isEmpty && game.recyclesUsed == 1)
        game.draw()
        let second = game.draw()
        #expect(second && game.recyclesUsed == 2)
        game.draw()
        let third = game.draw()
        #expect(!third, "no third recycle")
        #expect(game.waste.count == 1 && game.stock.isEmpty)
    }

    @Test func recycleOptionNever() {
        var game = pyramid(cards: [:], stock: [down(.clubs, 4)], recycles: 0)
        game.draw()
        #expect(!game.canRecycleWaste)
        let again = game.draw()
        #expect(!again)
    }

    @Test func recycleOptionOnce() {
        var game = pyramid(cards: [:], stock: [down(.clubs, 4)], recycles: 1)
        game.draw()
        let first = game.draw()
        #expect(first)
        game.draw()
        let second = game.draw()
        #expect(!second)
    }

    @Test func recycleOptionAlwaysNeverRunsOut() {
        var game = pyramid(cards: [:], stock: [down(.clubs, 4)], recycles: -1)
        for _ in 0..<20 {
            let drew = game.draw()
            #expect(drew)
        }
        #expect(game.canRecycleWaste || !game.stock.isEmpty)
    }

    @Test func recycleKeepsTheOrder() {
        var game = pyramid(cards: [:], stock: [down(.clubs, 3), down(.clubs, 2), down(.clubs, 1)], recycles: 1)
        game.draw(); game.draw(); game.draw()
        #expect(game.waste.map(\.rank) == [1, 2, 3])
        game.draw()
        #expect(game.stock.map(\.rank) == [3, 2, 1] && game.stock.allSatisfy { !$0.isFaceUp })
    }

    @Test func recycleOptionComesFromTheDeal() {
        var options = PyramidOptions()
        options.recycles = 0
        #expect(Pyramid(seed: 1, options: options).options.recycles == 0)
    }

    @Test func saveWithoutOptionsDecodesWithTheDefaults() throws {
        let game = Pyramid(seed: 3)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        object["options"] = nil
        let decoded = try Pyramid.decodeSaved(from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == game)
    }
}

@Suite struct PyramidHintTests {
    @Test func hintPrefersThePairThatFreesMoreCards() {
        // 21+22 (6+7) free position 15; 24+25 (5+8) free nothing, though it is listed first by position order.
        let game = pyramid(cards: [15: up(.hearts, 2), 21: up(.spades, 6), 22: up(.hearts, 7), 26: up(.clubs, 5), 27: up(.clubs, 8), 20: up(.clubs, 9)])
        #expect(game.hint == .move(Move(from: .tableau(21), index: 0, to: .tableau(22))))
    }

    @Test func hintAvoidsWastingACardThatHasAnotherPartner() {
        // Two 7s and a 6: the free-count is equal, so the lower position wins, but a lone pair beats a shared 6.
        let game = pyramid(cards: [21: up(.spades, 6), 22: up(.hearts, 7), 23: up(.clubs, 7), 24: up(.clubs, 3), 25: up(.hearts, 10)])
        let first = game.usefulMoves[0]
        #expect(first == Move(from: .tableau(24), index: 0, to: .tableau(25)), "3 + 10 uses cards nobody else wants")
    }

    @Test func hintTakesAKingAlone() {
        let game = pyramid(cards: [21: up(.spades, 13), 22: up(.hearts, 2)])
        #expect(game.hint == .move(Move(from: .tableau(21), index: 0, to: .foundation(0))))
    }

    @Test func hintUsesTheWaste() {
        let game = pyramid(cards: [21: up(.spades, 9)], waste: [up(.hearts, 4)], stock: [down(.clubs, 2)])
        #expect(game.hint == .move(Move(from: .tableau(21), index: 0, to: .waste)))
    }

    @Test func hintDrawsWhenNoPairIsLeft() {
        let game = pyramid(cards: [21: up(.spades, 9)], waste: [up(.hearts, 5)], stock: [down(.clubs, 4)])
        #expect(game.hint == .draw)
        #expect(!game.isStuck, "the 4 in the stock pairs with the 9")
    }

    @Test func hintDrawsToRecycleTheWasteWhileOneIsLeft() {
        let game = pyramid(cards: [21: up(.spades, 9)], waste: [up(.hearts, 4), up(.hearts, 5)], recycles: 1)
        #expect(game.hint == .draw)
        #expect(!game.isStuck, "the 4 under the 5 can come round again")
    }

    @Test func stuckWhenNothingPairsAndNothingCanComeRound() {
        let game = pyramid(cards: [21: up(.spades, 9)], waste: [up(.hearts, 4), up(.hearts, 5)], recycles: 0)
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func stuckWhenTheStockHoldsNoPartner() {
        let game = pyramid(cards: [21: up(.spades, 9)], stock: [down(.clubs, 2), down(.clubs, 3)], recycles: 0)
        #expect(game.hint == .draw, "drawing is still possible")
        #expect(game.isStuck, "but no card in the stock can pair with the 9")
    }

    @Test func aKingInTheStockIsNotStuck() {
        let game = pyramid(cards: [21: up(.spades, 9)], stock: [down(.clubs, 13)], recycles: 0)
        #expect(!game.isStuck)
    }
}

@Suite struct PyramidPlayTests {
    @Test func followingTheHintAlwaysEnds() {
        for seed in UInt64(0)..<30 {
            var game = Pyramid(seed: seed)
            var steps = 0
            while !game.isWon, !game.isStuck, steps < 1000, let hint = game.hint {
                switch hint {
                case .move(let move): game.apply(move)
                case .draw: game.draw()
                }
                steps += 1
            }
            #expect(steps < 1000, "seed \(seed) never ended")
            #expect(game.isWon || game.isStuck, "seed \(seed) stopped in a live position")
        }
    }
}
