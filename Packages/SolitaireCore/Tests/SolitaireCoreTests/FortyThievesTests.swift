import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: false) }

private func thieves(
    stock: [Card] = [], waste: [Card] = [], foundations: [[Card]] = Array(repeating: [], count: 8), columns: [[Card]]
) -> FortyThieves {
    FortyThieves(stock: stock, waste: waste, foundations: foundations, tableau: columns + Array(repeating: [], count: 10 - columns.count))
}

private func fullSuit(_ suit: Suit, upTo top: Int = 13) -> [Card] { (1...top).map { up(suit, $0) } }

@Suite struct FortyThievesDealTests {
    @Test func dealsTenColumnsOfFourFaceUpAndAStockOf64() {
        let game = FortyThieves(seed: 42)
        #expect(game.tableau.map(\.count) == Array(repeating: 4, count: 10))
        #expect(game.tableau.allSatisfy { $0.allSatisfy { $0.isFaceUp } })
        #expect(game.stock.count == 64)
        #expect(game.stock.allSatisfy { !$0.isFaceUp })
        #expect(game.waste.isEmpty)
        #expect(game.foundations.count == 8 && game.foundations.allSatisfy { $0.isEmpty })
        let ids = (game.tableau.flatMap { $0 } + game.stock).map(\.id)
        #expect(Set(ids).count == 104)
        #expect(game.moveCount == 0)
    }

    @Test func sameSeedSameDeal() {
        #expect(FortyThieves(seed: 5) == FortyThieves(seed: 5))
        #expect(FortyThieves(seed: 5).tableau != FortyThieves(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(FortyThieves(seed: seed).hint != nil)
            #expect(!FortyThieves(seed: seed).isStuck)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = FortyThieves(seed: .max)
        let drew = game.draw()
        #expect(drew)
        let decoded = try FortyThieves.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }
}

@Suite struct FortyThievesMoveTests {
    @Test func buildsDownInTheSameSuitOneCardAtATime() {
        let game = thieves(columns: [[up(.spades, 8)], [up(.spades, 7)], [up(.hearts, 7)], [up(.clubs, 9), up(.spades, 6), up(.spades, 5)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(0)), "another suit")
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "builds down, not up")
        #expect(!game.canPickUp(from: .tableau(3), at: 1), "only the top card moves")
        #expect(!game.canMove(from: .tableau(3), at: 1, to: .tableau(1)))
    }

    @Test func emptyColumnTakesAnyCard() {
        let game = thieves(waste: [up(.clubs, 3)], columns: [[up(.hearts, 5)], []])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
        #expect(game.canMove(from: .waste, at: 0, to: .tableau(1)))
    }

    @Test func wasteCardPlaysOntoAColumnAndIsRemoved() {
        var game = thieves(waste: [up(.clubs, 3), up(.spades, 7)], columns: [[up(.spades, 8)]])
        let ok = game.move(from: .waste, at: 1, to: .tableau(0))
        #expect(ok)
        #expect(game.waste.map(\.rank) == [3])
        #expect(game.tableau[0].map(\.rank) == [8, 7])
        #expect(game.moveCount == 1)
        #expect(!game.canPickUp(from: .waste, at: 5))
    }

    @Test func foundationsTakeAnAceThenTheSameSuitUpward() {
        var game = thieves(columns: [[up(.spades, 2), up(.spades, 1)], [up(.hearts, 1)], [up(.spades, 2)]])
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .foundation(0)), "needs the ace first")
        let ace = game.move(from: .tableau(0), at: 1, to: .foundation(0))
        #expect(ace)
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .foundation(0)), "another suit")
        #expect(game.canMove(from: .tableau(1), at: 0, to: .foundation(1)), "an ace goes on any empty foundation")
        let two = game.move(from: .tableau(0), at: 0, to: .foundation(0))
        #expect(two)
        #expect(game.foundations[0].map(\.rank) == [1, 2])
        #expect(game.tableau[0].isEmpty)
    }

    @Test func twoCopiesOfASuitUseTwoFoundations() {
        var game = thieves(columns: [[up(.spades, 1)], [Card(suit: .spades, rank: 1, isFaceUp: true, deck: 1)]])
        let first = game.move(from: .tableau(0), at: 0, to: .foundation(0))
        let second = game.move(from: .tableau(1), at: 0, to: .foundation(1))
        #expect(first && second)
    }

    @Test func foundationCardsStayThere() {
        let game = thieves(foundations: [[up(.spades, 1)]] + Array(repeating: [], count: 7), columns: [[up(.hearts, 2)], []])
        #expect(!game.canPickUp(from: .foundation(0), at: 0))
        #expect(!game.canMove(from: .foundation(0), at: 0, to: .tableau(1)))
    }

    @Test func illegalMoveChangesNothing() {
        var game = thieves(columns: [[up(.spades, 8)], [up(.hearts, 5)]])
        let before = game
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!ok)
        #expect(game == before)
        #expect(!game.canMove(from: .tableau(9), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(10)))
        #expect(!game.canMove(from: .tableau(0), at: 3, to: .tableau(1)))
        #expect(!game.canMove(from: .tableau(0), at: -1, to: .tableau(1)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .foundation(8)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .stock))
        #expect(game.cards(in: .tableau(10)).isEmpty)
        #expect(game.cards(in: .foundation(8)).isEmpty)
    }

    @Test func stockTurnsOneCardOntoTheWasteWithNoRedeal() {
        var game = thieves(stock: [down(.clubs, 3), down(.clubs, 2)], waste: [], columns: [[up(.hearts, 5)]])
        let first = game.draw()
        #expect(first)
        #expect(game.waste.map(\.rank) == [2])
        #expect(game.waste.last?.isFaceUp == true)
        let second = game.draw()
        #expect(second)
        let third = game.draw()
        #expect(!third, "no redeal")
        #expect(game.waste.map(\.rank) == [2, 3])
        #expect(game.moveCount == 2)
        #expect(!FortyThieves.recyclesWaste)
        #expect(!game.canRecycleWaste)
    }

    @Test func winsWhenAll104CardsAreOnTheFoundations() {
        var game = thieves(
            foundations: [fullSuit(.spades), fullSuit(.spades), fullSuit(.hearts), fullSuit(.hearts), fullSuit(.diamonds), fullSuit(.diamonds), fullSuit(.clubs), fullSuit(.clubs, upTo: 12)],
            columns: [[up(.clubs, 13)]]
        )
        #expect(!game.isWon)
        let ok = game.move(from: .tableau(0), at: 0, to: .foundation(7))
        #expect(ok)
        #expect(game.isWon)
    }

    @Test func tapSendsACardToAFoundationThenAColumn() {
        let game = thieves(columns: [[up(.spades, 1)], [up(.hearts, 6), up(.hearts, 8)], [up(.hearts, 7)]])
        #expect(game.bestDestination(from: .tableau(0), at: 0) == .foundation(0))
        #expect(game.bestDestination(from: .tableau(2), at: 0) == .tableau(1), "the 7 of hearts goes onto the 8")
    }

    @Test func finishPlaysOutWhenEveryRemainingCardCanGoUp() {
        let rest = [fullSuit(.spades), fullSuit(.spades), fullSuit(.hearts), fullSuit(.hearts), fullSuit(.diamonds), fullSuit(.diamonds), fullSuit(.clubs)]
        let ready = thieves(foundations: rest + [fullSuit(.clubs, upTo: 11)], columns: [[up(.clubs, 13), up(.clubs, 12)]])
        #expect(ready.canAutoComplete)
        var game = ready
        while let move = game.nextAutoMove() { game.apply(move) }
        #expect(game.isWon)
        let blocked = thieves(foundations: rest + [fullSuit(.clubs, upTo: 11)], columns: [[up(.clubs, 12), up(.clubs, 13)]])
        #expect(!blocked.canAutoComplete, "the king covers the queen")
        let stocked = thieves(stock: [down(.clubs, 12)], foundations: rest + [fullSuit(.clubs, upTo: 11)], columns: [[up(.clubs, 13)]])
        #expect(!stocked.canAutoComplete, "the stock has not been played")
    }
}

@Suite struct FortyThievesHintTests {
    @Test func aFoundationMoveComesFirstAndTheWasteBeatsColumns() {
        let game = thieves(waste: [up(.hearts, 1)], columns: [[up(.spades, 1)], [up(.clubs, 9)], [up(.clubs, 8)]])
        #expect(game.hint == .move(Move(from: .waste, index: 0, to: .foundation(0))))
    }

    @Test func movingATopCardOffAFoundationCardComesNext() {
        let game = thieves(
            foundations: [fullSuit(.spades, upTo: 4)] + Array(repeating: [], count: 7),
            columns: [[up(.spades, 5), up(.hearts, 3)], [up(.hearts, 4)], [up(.clubs, 9)]]
        )
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))), "frees the 5 of spades")
    }

    @Test func wasteCardOntoItsSuitBeatsDrawing() {
        let game = thieves(stock: [down(.clubs, 2)], waste: [up(.hearts, 7)], columns: [[up(.clubs, 9)], [up(.hearts, 8)]])
        #expect(game.hint == .move(Move(from: .waste, index: 0, to: .tableau(1))))
    }

    @Test func aLoneCardJoinsBeforeACardFromALongerColumn() {
        let game = thieves(columns: [[up(.clubs, 9), up(.hearts, 7)], [up(.hearts, 8)], [up(.spades, 7)], [up(.spades, 8)]])
        #expect(game.hint == .move(Move(from: .tableau(2), index: 0, to: .tableau(3))), "empties a column")
    }

    @Test func aCardNeverLeavesTheCardOfItsSuitItSitsOn() {
        let game = thieves(columns: [[up(.hearts, 8), up(.hearts, 7)], [up(.hearts, 8)]])
        #expect(game.usefulMoves.isEmpty)
    }

    @Test func drawingIsTheHintWhenNothingElseHelps() {
        let game = thieves(stock: [down(.clubs, 2)], columns: [[up(.clubs, 9)], [up(.hearts, 5)]])
        #expect(game.hint == .draw)
        #expect(!game.isStuck)
    }

    @Test func stuckWithAnEmptyStockAndNoMoves() {
        let game = thieves(waste: [up(.clubs, 2)], columns: (0..<10).map { [up(.hearts, $0 % 2 == 0 ? 3 : 10)] })
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func wasteCardToAnEmptyColumnIsTheLastResort() {
        let game = thieves(waste: [up(.clubs, 2)], columns: [[up(.hearts, 9)]])
        #expect(game.hint == .move(Move(from: .waste, index: 0, to: .tableau(1))))
        let withStock = thieves(stock: [down(.clubs, 3)], waste: [up(.clubs, 2)], columns: [[up(.hearts, 9)]])
        #expect(withStock.hint == .draw)
    }

    @Test func followingTheHintNeverLoops() {
        for seed in UInt64(0)..<30 {
            var game = FortyThieves(seed: seed)
            var steps = 0
            while let hint = game.hint, !game.isWon, steps < 1500 {
                switch hint {
                case .move(let move):
                    let applied = game.apply(move)
                    #expect(applied)
                case .draw:
                    let drew = game.draw()
                    #expect(drew)
                }
                steps += 1
            }
            #expect(steps < 1500, "seed \(seed)")
        }
    }
}
