import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }

private func eightOff(
    cells: [[Card]] = Array(repeating: [], count: 8), foundations: [[Card]] = [[], [], [], []], columns: [[Card]],
    options: EightOffOptions = EightOffOptions()
) -> EightOff {
    EightOff(cells: cells, foundations: foundations, tableau: columns + Array(repeating: [], count: 8 - columns.count), options: options)
}

@Suite struct EightOffDealTests {
    @Test func dealsEightColumnsAndFourCellCards() {
        let game = EightOff(seed: 42)
        #expect(game.tableau.map(\.count) == Array(repeating: 6, count: 8))
        #expect(game.cells.map(\.count) == [1, 1, 1, 1, 0, 0, 0, 0])
        #expect((game.tableau + game.cells).allSatisfy { $0.allSatisfy { $0.isFaceUp } })
        #expect(game.foundations.allSatisfy { $0.isEmpty })
        #expect(Set((game.tableau + game.cells).flatMap { $0 }.map(\.id)).count == 52)
    }

    @Test func sameSeedSameDeal() {
        #expect(EightOff(seed: 5) == EightOff(seed: 5))
        #expect(EightOff(seed: 5).tableau != EightOff(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(EightOff(seed: seed).hint != nil)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = EightOff(seed: .max)
        let move = try #require(game.usefulMoves.first)
        let moved = game.apply(move)
        #expect(moved)
        let decoded = try EightOff.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }

    @Test func saveWithoutOptionsDecodesWithTheDefaults() throws {
        let game = EightOff(seed: 3)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        object["options"] = nil
        let decoded = try EightOff.decodeSaved(from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == game)
        #expect(!decoded.options.anyCardInEmptyColumn)
    }
}

@Suite struct EightOffMoveTests {
    @Test func buildsDownInSuit() {
        let game = eightOff(columns: [[up(.spades, 8)], [up(.spades, 7)], [up(.hearts, 7)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(0)), "another suit")
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "builds down, not up")
    }

    @Test func onlySameSuitRunsPickUp() {
        let game = eightOff(columns: [[up(.spades, 9), up(.spades, 8), up(.hearts, 7)], [up(.hearts, 6), up(.hearts, 5)]])
        #expect(!game.canPickUp(from: .tableau(0), at: 0))
        #expect(!game.canPickUp(from: .tableau(0), at: 1))
        #expect(game.canPickUp(from: .tableau(1), at: 0))
    }

    @Test func runLimitFollowsFreeCellsAndEmptyColumns() {
        let run = (5...9).reversed().map { up(.clubs, $0) }
        let target = [up(.clubs, 10)]
        // Eight columns, two used, so six are empty: 9 cards fit with every cell free.
        let roomy = eightOff(columns: [run, target])
        #expect(roomy.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
        // Fill every column and seven cells: one free cell means two cards at most.
        var cells = Array(repeating: [up(.hearts, 2)], count: 7)
        cells.append([])
        let filler = (0..<6).map { [up(.diamonds, 13 - $0)] }
        let tight = eightOff(cells: cells, columns: [run, target] + filler)
        #expect(!tight.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "5 cards, one free cell")
        #expect(!tight.canMove(from: .tableau(0), at: 3, to: .tableau(1)), "the 6 isn't a club 9")
        let twoCards = eightOff(cells: cells, columns: [[up(.clubs, 6), up(.clubs, 5)], [up(.clubs, 7)]] + filler)
        #expect(twoCards.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
        let threeCards = eightOff(cells: cells, columns: [[up(.clubs, 7), up(.clubs, 6), up(.clubs, 5)], [up(.clubs, 8)]] + filler)
        #expect(!threeCards.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
    }

    @Test func emptyColumnTakesKingsOnlyByDefault() {
        let game = eightOff(columns: [[up(.spades, 9), up(.hearts, 4)], [up(.clubs, 13), up(.clubs, 12)], [up(.hearts, 13)]])
        #expect(!game.canMove(from: .tableau(0), at: 1, to: .tableau(5)))
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(5)), "a run led by a king")
        #expect(!game.canMove(from: .tableau(1), at: 1, to: .tableau(5)))
        #expect(!game.canMove(from: .cell(0), at: 0, to: .tableau(5)), "an empty cell holds nothing")
    }

    @Test func anyCardOptionOpensEmptyColumns() {
        var options = EightOffOptions()
        options.anyCardInEmptyColumn = true
        let game = eightOff(columns: [[up(.spades, 9), up(.hearts, 4)]], options: options)
        #expect(game.canMove(from: .tableau(0), at: 1, to: .tableau(5)))
        let kingsOnly = eightOff(columns: [[up(.spades, 9), up(.hearts, 4)]])
        #expect(!kingsOnly.canMove(from: .tableau(0), at: 1, to: .tableau(5)))
    }

    @Test func freeCellsHoldOneCardEach() {
        var game = eightOff(columns: [[up(.spades, 8), up(.hearts, 4)], [up(.clubs, 2), up(.diamonds, 9)]])
        let moved = game.move(from: .tableau(0), at: 1, to: .cell(0))
        #expect(moved)
        #expect(!game.canMove(from: .tableau(1), at: 1, to: .cell(0)))
        #expect(game.canMove(from: .tableau(1), at: 1, to: .cell(7)))
        #expect(game.moveCount == 1)
    }

    @Test func illegalMoveChangesNothing() {
        var game = eightOff(columns: [[up(.spades, 8)], [up(.hearts, 5)]])
        let before = game
        let moved = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!moved)
        #expect(game == before)
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(99)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .cell(99)))
        #expect(game.cards(in: .cell(99)).isEmpty)
    }

    @Test func winAndAutoComplete() {
        let full = Suit.allCases.map { suit in (1...13).map { up(suit, $0) } }
        #expect(eightOff(foundations: full, columns: []).isWon)
        var game = eightOff(columns: Suit.allCases.map { suit in (1...13).reversed().map { up(suit, $0) } })
        #expect(game.canAutoComplete)
        while let move = game.nextAutoMove() { game.apply(move) }
        #expect(game.isWon)
        #expect(!eightOff(columns: [[up(.spades, 2), up(.hearts, 9)]]).canAutoComplete)
    }
}

@Suite struct EightOffHintTests {
    @Test func foundationFirst() {
        let game = eightOff(cells: [[up(.hearts, 1)]] + Array(repeating: [], count: 7), columns: [[up(.spades, 5)], [up(.clubs, 1)]])
        #expect(game.hint == .move(Move(from: .cell(0), index: 0, to: .foundation(0))))
    }

    @Test func freesANeededCardFromBelowARunOnAColumn() {
        // The ace of spades is under the 6 and 5 of clubs; the run goes onto the 7 of clubs.
        let game = eightOff(columns: [[up(.spades, 1), up(.clubs, 6), up(.clubs, 5)], [up(.clubs, 7), up(.hearts, 3)], [up(.clubs, 7)]])
        let hint = game.hint
        #expect(hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(2))))
    }

    @Test func parksTheTopCardInACellWhenNothingElseFreesTheAce() {
        let game = eightOff(columns: [[up(.spades, 1), up(.hearts, 9)], [up(.clubs, 3)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .cell(0))))
    }

    @Test func stuckWhenOnlyPointlessMovesRemain() {
        // The 5 already sits on the 6 of its suit: moving it elsewhere gets nowhere.
        let game = eightOff(columns: [[up(.clubs, 9), up(.spades, 6), up(.spades, 5)], [up(.hearts, 9)]])
        #expect(game.usefulMoves.isEmpty)
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func aFreeCellCardBuriesANeededCardOnlyWhenEveryCellIsFull() {
        // The 4 of hearts fits only on the 5 of hearts, over the ace of spades.
        let columns = [[up(.spades, 1), up(.hearts, 5)], [up(.clubs, 9)]] + (0..<6).map { _ in [up(.clubs, 2)] }
        let full = eightOff(cells: (0..<8).map { _ in [up(.diamonds, 4)] }, columns: columns)
        #expect(full.hint == nil, "no cell card fits")
        var cells = (0..<8).map { _ in [up(.diamonds, 13)] }
        cells[3] = [up(.hearts, 4)]
        let allFull = eightOff(cells: cells, columns: columns)
        #expect(allFull.hint == .move(Move(from: .cell(3), index: 0, to: .tableau(0))))
        cells[7] = []
        let oneSpare = eightOff(cells: cells, columns: columns)
        #expect(oneSpare.hint == nil, "a spare cell would only take the 4 back")
    }

    @Test func followingTheHintNeverRunsInCircles() {
        for seed in UInt64(0)..<30 {
            var game = EightOff(seed: seed)
            var steps = 0
            while let hint = game.hint, case .move(let move) = hint, steps < 600 {
                game.apply(move)
                steps += 1
            }
            #expect(steps < 600, "seed \(seed) looped")
        }
    }
}
