import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: false) }

private func scorpion(stock: [Card] = [], foundations: [[Card]] = [[], [], [], []], columns: [[Card]]) -> Scorpion {
    Scorpion(stock: stock, foundations: foundations, tableau: columns + Array(repeating: [], count: 7 - columns.count))
}

/// A suit from king down to `rank`.
private func run(_ suit: Suit, from high: Int = 13, to low: Int) -> [Card] {
    stride(from: high, through: low, by: -1).map { up(suit, $0) }
}

private func fullSuit(_ suit: Suit) -> [Card] { (1...13).map { up(suit, $0) } }

@Suite struct ScorpionDealTests {
    @Test func dealsSevenColumnsAndAReserve() {
        let game = Scorpion(seed: 42)
        #expect(game.tableau.allSatisfy { $0.count == 7 })
        #expect(game.stock.count == 3)
        #expect(game.stock.allSatisfy { !$0.isFaceUp })
        for column in 0..<4 {
            #expect(game.tableau[column].map(\.isFaceUp) == [false, false, false, true, true, true, true])
        }
        for column in 4..<7 {
            #expect(game.tableau[column].allSatisfy { $0.isFaceUp })
        }
        #expect(Set((game.tableau.flatMap { $0 } + game.stock).map(\.id)).count == 52)
    }

    @Test func sameSeedSameDeal() {
        #expect(Scorpion(seed: 5) == Scorpion(seed: 5))
        #expect(Scorpion(seed: 5).tableau != Scorpion(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(Scorpion(seed: seed).hint != nil)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = Scorpion(seed: .max)
        let dealt = game.draw()
        #expect(dealt)
        let decoded = try Scorpion.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }
}

@Suite struct ScorpionMoveTests {
    @Test func buildsDownInTheSameSuit() {
        let game = scorpion(columns: [[up(.spades, 8)], [up(.spades, 7)], [up(.hearts, 7)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(0)), "another suit")
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "builds down, not up")
    }

    @Test func anyFaceUpCardMovesWithWhatIsOnIt() {
        var game = scorpion(columns: [[up(.spades, 8)], [up(.spades, 7), up(.clubs, 2)]])
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(ok)
        #expect(game.tableau[0].map(\.rank) == [8, 7, 2])
        #expect(game.moveCount == 1)
    }

    @Test func faceDownCardsCannotMoveAndTurnUpWhenUncovered() {
        var game = scorpion(columns: [[down(.clubs, 5), up(.hearts, 7)], [up(.hearts, 8)], [down(.spades, 2)]])
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(1)))
        let ok = game.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(ok)
        #expect(game.tableau[0].map(\.isFaceUp) == [true])
    }

    @Test func emptyColumnTakesOnlyKings() {
        let game = scorpion(columns: [[up(.spades, 13), up(.spades, 12)], [up(.clubs, 12)], [], []])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .tableau(2)))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .tableau(2)))
    }

    @Test func illegalMoveChangesNothing() {
        var game = scorpion(columns: [[up(.spades, 8)], [up(.hearts, 7)]])
        let before = game
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!ok)
        #expect(game == before)
        #expect(!game.canMove(from: .tableau(9), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(9)))
        #expect(!game.canMove(from: .tableau(0), at: 3, to: .tableau(1)))
        #expect(!game.canMove(from: .foundation(0), at: 0, to: .tableau(1)))
        #expect(game.cards(in: .tableau(9)).isEmpty)
        #expect(game.cards(in: .foundation(9)).isEmpty)
    }

    @Test func cardsCannotBeMovedToAFoundationByHand() {
        let game = scorpion(columns: [[up(.spades, 1)]])
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
    }

    @Test func reserveDealsOneCardOntoEachOfTheFirstThreeColumnsOnce() {
        var game = scorpion(stock: [down(.clubs, 3), down(.clubs, 2), down(.clubs, 1)], columns: [[up(.spades, 9)], [], [up(.hearts, 4)], [up(.hearts, 5)]])
        let dealt = game.draw()
        #expect(dealt)
        #expect(game.stock.isEmpty)
        #expect(game.tableau.prefix(3).map { $0.last?.rank } == [1, 2, 3])
        #expect(game.tableau.prefix(3).allSatisfy { $0.last?.isFaceUp == true })
        #expect(game.tableau[3].count == 1)
        #expect(game.moveCount == 1)
        let again = game.draw()
        #expect(!again)
        #expect(game.moveCount == 1)
    }

    @Test func aCompleteRunLeavesForAFoundationAtOnce() {
        // Kings down to the 2 of spades in column 2; the ace arrives from column 1 and the run goes.
        var game = scorpion(columns: [[down(.hearts, 5), up(.spades, 1)], run(.spades, to: 2)])
        let ok = game.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(ok)
        #expect(game.tableau[1].isEmpty)
        #expect(game.foundations[0].map(\.rank) == Array((1...13).reversed()))
        #expect(game.tableau[0].map(\.isFaceUp) == [true], "the card it uncovered turns up")
        #expect(game.moveCount == 1, "one undo step")
    }

    @Test func aRunDealtFromTheReserveLeavesToo() {
        var game = scorpion(stock: [down(.clubs, 3), down(.clubs, 2), down(.spades, 1)], columns: [run(.spades, to: 2)])
        let dealt = game.draw()
        #expect(dealt)
        #expect(game.tableau[0].isEmpty)
        #expect(game.foundations.filter { !$0.isEmpty }.count == 1)
    }

    @Test func aRunThatDoesNotStartWithAKingStays() {
        var game = scorpion(columns: [[up(.hearts, 5), up(.spades, 1)].prefix(0) + [up(.hearts, 5)], run(.spades, from: 12, to: 2), [up(.spades, 1)]])
        let ok = game.move(from: .tableau(2), at: 0, to: .tableau(1))
        #expect(ok)
        #expect(game.tableau[1].count == 12)
        #expect(game.foundations.allSatisfy { $0.isEmpty })
    }

    @Test func winsWhenFourRunsAreOut() {
        var game = scorpion(
            foundations: [fullSuit(.spades), fullSuit(.hearts), fullSuit(.diamonds), []],
            columns: [[up(.clubs, 1)], run(.clubs, to: 2)]
        )
        #expect(!game.isWon)
        let ok = game.move(from: .tableau(0), at: 0, to: .tableau(1))
        #expect(ok)
        #expect(game.isWon)
    }
}

@Suite struct ScorpionHintTests {
    @Test func aMoveThatCompletesARunComesFirst() {
        let game = scorpion(columns: [[down(.hearts, 5), up(.clubs, 9)], [up(.hearts, 6)], run(.spades, to: 2), [up(.spades, 1)]])
        #expect(game.hint == .move(Move(from: .tableau(3), index: 0, to: .tableau(2))))
    }

    @Test func turningUpACardBeatsOtherMoves() {
        let game = scorpion(columns: [
            [down(.clubs, 5), up(.hearts, 7)], [up(.hearts, 8)],
            [up(.spades, 9)], [up(.spades, 8)],
        ])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
    }

    @Test func prefersTheColumnWithMostHiddenCards() {
        let game = scorpion(columns: [
            [down(.clubs, 5), up(.hearts, 7)],
            [down(.clubs, 6), down(.clubs, 9), down(.clubs, 10), up(.spades, 7)],
            [up(.hearts, 8)], [up(.spades, 8)],
        ])
        #expect(game.hint == .move(Move(from: .tableau(1), index: 3, to: .tableau(3))))
    }

    @Test func doesNotSplitCardsThatAlreadyFit() {
        let game = scorpion(columns: [[up(.hearts, 8), up(.hearts, 7)], [up(.hearts, 9)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 0, to: .tableau(1))), "only the whole column moves")
        let joined = scorpion(columns: [[up(.hearts, 9), up(.hearts, 8), up(.hearts, 7)]])
        #expect(joined.hint == nil)
    }

    @Test func reserveIsTheHintWhenNothingElseHelps() {
        let game = scorpion(stock: [down(.clubs, 3), down(.clubs, 2), down(.clubs, 1)], columns: [[up(.hearts, 9)], [up(.spades, 5)]])
        #expect(game.usefulMoves.isEmpty)
        #expect(game.hint == .draw)
        #expect(!game.isStuck)
    }

    @Test func stuckWithAnEmptyReserveAndNoMoves() {
        let game = scorpion(columns: [[up(.hearts, 9)], [up(.spades, 5)]])
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func aKingGoesToAnEmptyColumnOnlyToUncover() {
        let covered = scorpion(columns: [[down(.clubs, 5), up(.spades, 13)], []])
        #expect(covered.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
        let alone = scorpion(columns: [[up(.spades, 13)], []])
        #expect(alone.isStuck)
    }

    @Test func followingTheHintNeverLoops() {
        for seed in UInt64(0)..<20 {
            var game = Scorpion(seed: seed)
            var steps = 0
            while let hint = game.hint, !game.isWon, steps < 500 {
                switch hint {
                case .move(let move):
                    let applied = game.apply(move)
                    #expect(applied)
                case .draw:
                    let dealt = game.draw()
                    #expect(dealt)
                }
                steps += 1
            }
            #expect(steps < 500)
        }
    }
}
