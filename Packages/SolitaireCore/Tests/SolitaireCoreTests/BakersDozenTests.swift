import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }

private func bakers(foundations: [[Card]] = [[], [], [], []], columns: [[Card]]) -> BakersDozen {
    BakersDozen(foundations: foundations, tableau: columns + Array(repeating: [], count: 13 - columns.count))
}

@Suite struct BakersDozenDealTests {
    @Test func dealsThirteenColumnsOfFourFaceUp() {
        let game = BakersDozen(seed: 42)
        #expect(game.tableau.count == 13)
        #expect(game.tableau.allSatisfy { $0.count == 4 })
        #expect(game.tableau.allSatisfy { $0.allSatisfy { $0.isFaceUp } })
        #expect(game.foundations.allSatisfy { $0.isEmpty })
        #expect(Set(game.tableau.flatMap { $0 }.map(\.id)).count == 52)
    }

    @Test func kingsSitAtTheBottomOfTheirColumn() {
        for seed in UInt64(0)..<50 {
            for column in BakersDozen(seed: seed).tableau {
                let ranks = column.map(\.rank)
                let kings = ranks.prefix { $0 == 13 }.count
                #expect(!ranks.dropFirst(kings).contains(13))
            }
        }
    }

    @Test func sameSeedSameDeal() {
        #expect(BakersDozen(seed: 5) == BakersDozen(seed: 5))
        #expect(BakersDozen(seed: 5).tableau != BakersDozen(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(BakersDozen(seed: seed).hint != nil)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = BakersDozen(seed: .max)
        let move = try #require(game.usefulMoves.first)
        let moved = game.apply(move)
        #expect(moved)
        let decoded = try BakersDozen.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }
}

@Suite struct BakersDozenMoveTests {
    @Test func buildsDownInAnySuit() {
        let game = bakers(columns: [[up(.spades, 8)], [up(.hearts, 7)], [up(.spades, 7)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(game.canMove(from: .tableau(2), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "builds down, not up")
    }

    @Test func movesOneCardAtATime() {
        let game = bakers(columns: [[up(.spades, 9)], [up(.hearts, 8), up(.clubs, 7)]])
        #expect(!game.canPickUp(from: .tableau(1), at: 0))
        #expect(game.canPickUp(from: .tableau(1), at: 1))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .tableau(0)), "a run doesn't move together")
    }

    @Test func emptyColumnsStayEmpty() {
        let game = bakers(columns: [[up(.spades, 8), up(.hearts, 4)], [up(.clubs, 13)]])
        #expect(!game.canMove(from: .tableau(0), at: 1, to: .tableau(5)))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .tableau(5)), "not even a king")
    }

    @Test func illegalMoveChangesNothing() {
        var game = bakers(columns: [[up(.spades, 8)], [up(.hearts, 5)]])
        let before = game
        let moved = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!moved)
        #expect(game == before)
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(99)))
        #expect(game.cards(in: .tableau(99)).isEmpty)
        #expect(!game.canMove(from: .cell(0), at: 0, to: .tableau(0)))
    }

    @Test func foundationsBuildUpInSuit() {
        var game = bakers(columns: [[up(.spades, 1)], [up(.hearts, 1)], [up(.spades, 2)]])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
        let first = game.move(from: .tableau(0), at: 0, to: .foundation(0))
        #expect(first)
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .foundation(0)))
        #expect(game.canMove(from: .tableau(2), at: 0, to: .foundation(0)))
        #expect(!game.canMove(from: .foundation(0), at: 0, to: .tableau(1)), "foundation cards stay")
        #expect(game.moveCount == 1)
    }

    @Test func winWhenEverythingIsOnTheFoundations() {
        let full = Suit.allCases.map { suit in (1...13).map { up(suit, $0) } }
        let game = bakers(foundations: full, columns: [])
        #expect(game.isWon)
        #expect(!game.isStuck)
        #expect(!game.canAutoComplete)
    }

    @Test func autoCompleteWhenColumnsRunDown() {
        let game = bakers(columns: Suit.allCases.map { suit in (1...13).reversed().map { up(suit, $0) } })
        #expect(game.canAutoComplete)
        #expect(game.nextAutoMove() != nil)
        let tangled = bakers(columns: [[up(.spades, 2), up(.hearts, 9)]])
        #expect(!tangled.canAutoComplete)
    }

    @Test func autoCompleteFinishesTheGame() {
        var game = bakers(columns: Suit.allCases.map { suit in (1...13).reversed().map { up(suit, $0) } })
        while let move = game.nextAutoMove() { game.apply(move) }
        #expect(game.isWon)
    }
}

@Suite struct BakersDozenHintTests {
    @Test func foundationFirst() {
        let game = bakers(columns: [[up(.spades, 5)], [up(.hearts, 4)], [up(.clubs, 1)]])
        #expect(game.hint == .move(Move(from: .tableau(2), index: 0, to: .foundation(0))))
    }

    @Test func freesANeededCardBeforeTidying() {
        // The ace of spades is under the 6; the 3 could also go on the 4.
        let game = bakers(columns: [[up(.spades, 1), up(.clubs, 6)], [up(.hearts, 7)], [up(.hearts, 4)], [up(.clubs, 3), up(.diamonds, 9)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
    }

    @Test func doesNotBuryANeededCardWhenThereIsAChoice() {
        // The 6 can go on the 7 over the ace of spades, or on the 7 of hearts.
        let game = bakers(columns: [[up(.clubs, 9), up(.diamonds, 6)], [up(.spades, 1), up(.spades, 7)], [up(.hearts, 7)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(2))))
    }

    @Test func aCardAlreadyOnTheNextRankUpStays() {
        // The 5 sits on the 6 and could go on the other 6: pointless, so nothing is left and the game is stuck.
        let game = bakers(columns: [[up(.clubs, 9), up(.spades, 6), up(.hearts, 5)], [up(.diamonds, 8), up(.clubs, 6)]])
        #expect(game.canMove(from: .tableau(0), at: 2, to: .tableau(1)))
        #expect(game.usefulMoves.isEmpty)
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func followingTheHintNeverRunsInCircles() {
        for seed in UInt64(0)..<30 {
            var game = BakersDozen(seed: seed)
            var steps = 0
            while let hint = game.hint, case .move(let move) = hint, steps < 400 {
                game.apply(move)
                steps += 1
            }
            #expect(steps < 400, "seed \(seed) looped")
        }
    }
}
