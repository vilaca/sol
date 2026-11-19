import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: false) }

private func yukon(foundations: [[Card]] = [[], [], [], []], columns: [[Card]]) -> Yukon {
    Yukon(foundations: foundations, tableau: columns + Array(repeating: [], count: 7 - columns.count))
}

private func suit(_ suit: Suit, upTo rank: Int) -> [Card] {
    rank == 0 ? [] : (1...rank).map { up(suit, $0) }
}

@Suite struct YukonDealTests {
    @Test func dealsSevenColumns() {
        let game = Yukon(seed: 42)
        #expect(game.tableau.map(\.count) == [1, 6, 7, 8, 9, 10, 11])
        #expect(game.tableau.map { $0.filter { !$0.isFaceUp }.count } == [0, 1, 2, 3, 4, 5, 6])
        for column in game.tableau {
            let hidden = column.prefix { !$0.isFaceUp }.count
            #expect(column.dropFirst(hidden).allSatisfy { $0.isFaceUp })
        }
        #expect(game.tableau.dropFirst().allSatisfy { $0.suffix(5).allSatisfy { $0.isFaceUp } })
        #expect(Set(game.tableau.flatMap { $0 }.map(\.id)).count == 52)
        #expect(game.foundations.allSatisfy { $0.isEmpty })
    }

    @Test func sameSeedSameDeal() {
        #expect(Yukon(seed: 5) == Yukon(seed: 5))
        #expect(Yukon(seed: 5).tableau != Yukon(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(Yukon(seed: seed).hint != nil)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = Yukon(seed: .max)
        let move = try #require(game.usefulMoves.first)
        let applied = game.apply(move)
        #expect(applied)
        let decoded = try Yukon.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }
}

@Suite struct YukonMoveTests {
    @Test func anyFaceUpCardMovesWithWhatIsOnIt() {
        // The 7 of hearts sits under a 2 of clubs, which is not in sequence with it.
        let game = yukon(columns: [[up(.spades, 8)], [up(.hearts, 7), up(.clubs, 2)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        var moved = game
        let ok = moved.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(ok)
        #expect(moved.tableau[0].map(\.rank) == [8, 7, 2])
        #expect(moved.moveCount == 1)
    }

    @Test func buildsDownInAlternatingColours() {
        let game = yukon(columns: [[up(.spades, 8)], [up(.clubs, 7)], [up(.hearts, 7)], [up(.hearts, 9)]])
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .tableau(0)), "same colour")
        #expect(game.canMove(from: .tableau(2), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(2)), "builds down, not up")
        #expect(!game.canMove(from: .tableau(3), at: 0, to: .tableau(0)), "two ranks apart")
    }

    @Test func faceDownCardsCannotMoveAndTurnUpWhenUncovered() {
        let game = yukon(columns: [[down(.clubs, 5), up(.hearts, 7)], [up(.spades, 8)], [down(.spades, 2)]])
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(1)))
        var moved = game
        let ok = moved.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(ok)
        #expect(moved.tableau[0].map(\.isFaceUp) == [true])
    }

    @Test func emptyColumnTakesOnlyKings() {
        let game = yukon(columns: [[up(.spades, 13), up(.hearts, 12)], [up(.clubs, 12)], [], []])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .tableau(2)))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .tableau(2)))
    }

    @Test func foundationsBuildUpBySuitFromTheAce() {
        let game = yukon(foundations: [suit(.hearts, upTo: 2), [], [], []], columns: [[up(.hearts, 3)], [up(.spades, 3)], [up(.spades, 1)]])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .foundation(0)))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .foundation(1)), "needs an ace first")
        #expect(game.canMove(from: .tableau(2), at: 0, to: .foundation(1)))
    }

    @Test func onlyTheTopCardGoesToAFoundation() {
        let game = yukon(columns: [[up(.spades, 1), up(.hearts, 5)]])
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
    }

    @Test func illegalMoveChangesNothing() {
        var game = yukon(columns: [[up(.spades, 8)], [up(.clubs, 7)]])
        let before = game
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!ok)
        #expect(game == before)
        #expect(!game.canMove(from: .tableau(9), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(9)))
        #expect(!game.canMove(from: .tableau(0), at: 5, to: .tableau(1)))
        #expect(game.cards(in: .tableau(9)).isEmpty)
    }

    @Test func winsWhenEveryFoundationIsComplete() {
        var game = yukon(
            foundations: [suit(.spades, upTo: 13), suit(.hearts, upTo: 13), suit(.diamonds, upTo: 13), suit(.clubs, upTo: 12)],
            columns: [[up(.clubs, 13)]]
        )
        #expect(!game.isWon)
        let ok = game.move(from: .tableau(0), at: 0, to: .foundation(3))
        #expect(ok)
        #expect(game.isWon)
    }

    @Test func autoCompletesOnceEverythingIsFaceUpAndOrdered() {
        let game = yukon(columns: [[up(.spades, 5), up(.hearts, 3)], [up(.clubs, 4)]])
        #expect(game.canAutoComplete)
        #expect(!yukon(columns: [[up(.spades, 3), up(.hearts, 5)]]).canAutoComplete)
        #expect(!yukon(columns: [[down(.spades, 5), up(.hearts, 3)]]).canAutoComplete)
    }
}

@Suite struct YukonHintTests {
    @Test func foundationMovesComeFirst() {
        let game = yukon(columns: [[down(.clubs, 5), up(.hearts, 7)], [up(.spades, 8)], [up(.diamonds, 1)]])
        #expect(game.hint == .move(Move(from: .tableau(2), index: 0, to: .foundation(0))))
    }

    @Test func turningUpACardBeatsOtherMoves() {
        let game = yukon(columns: [[up(.spades, 9)], [up(.hearts, 8)], [down(.clubs, 5), up(.hearts, 7)], [up(.spades, 8)]])
        #expect(game.hint == .move(Move(from: .tableau(2), index: 1, to: .tableau(3))))
    }

    @Test func prefersTheColumnWithMostHiddenCards() {
        let game = yukon(columns: [
            [down(.clubs, 5), up(.hearts, 7)],
            [down(.clubs, 6), down(.clubs, 9), down(.clubs, 10), up(.hearts, 7)],
            [up(.spades, 8)],
        ])
        #expect(game.hint == .move(Move(from: .tableau(1), index: 3, to: .tableau(2))))
    }

    @Test func freesACardTheFoundationsNeed() {
        let game = yukon(columns: [[up(.spades, 1), up(.hearts, 5)], [up(.clubs, 6)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
    }

    @Test func doesNotSplitCardsThatAlreadyFit() {
        // The 6 of clubs already sits on the 7 of hearts; moving it onto the 7 of diamonds gains nothing.
        let game = yukon(columns: [[up(.hearts, 7), up(.clubs, 6)], [up(.diamonds, 7)]])
        #expect(game.usefulMoves.isEmpty)
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func aWholeColumnMovesOntoAnotherToEmptyIt() {
        let game = yukon(columns: [[up(.hearts, 7), up(.clubs, 6)], [up(.spades, 8)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 0, to: .tableau(1))))
    }

    @Test func aKingGoesToAnEmptyColumnOnlyToUncover() {
        let covered = yukon(columns: [[down(.clubs, 5), up(.spades, 13)], []])
        #expect(covered.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
        let alone = yukon(columns: [[up(.spades, 13)], []])
        #expect(alone.hint == nil)
        #expect(alone.isStuck)
    }

    @Test func wonGameIsNotStuck() {
        let game = yukon(foundations: [suit(.spades, upTo: 13), suit(.hearts, upTo: 13), suit(.diamonds, upTo: 13), suit(.clubs, upTo: 13)], columns: [])
        #expect(game.isWon)
        #expect(!game.isStuck)
    }

    @Test func followingTheHintNeverLoops() {
        for seed in UInt64(0)..<20 {
            var game = Yukon(seed: seed)
            var steps = 0
            while case .move(let move)? = game.hint, !game.isWon, steps < 500 {
                let applied = game.apply(move)
                #expect(applied)
                steps += 1
            }
            #expect(steps < 500)
        }
    }
}
