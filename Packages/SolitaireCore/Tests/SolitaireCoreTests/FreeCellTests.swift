import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }

private func freeCell(cells: [[Card]] = [[], [], [], []], foundations: [[Card]] = [[], [], [], []], columns: [[Card]]) -> FreeCell {
    FreeCell(cells: cells, foundations: foundations, tableau: columns + Array(repeating: [], count: 8 - columns.count))
}

/// The suit from ace up to `rank`, for a foundation.
private func suit(_ suit: Suit, upTo rank: Int) -> [Card] {
    rank == 0 ? [] : (1...rank).map { up(suit, $0) }
}

@Suite struct FreeCellDealTests {
    @Test func dealsEightColumnsFaceUp() {
        let game = FreeCell(seed: 42)
        #expect(game.tableau.map(\.count) == [7, 7, 7, 7, 6, 6, 6, 6])
        #expect(game.tableau.allSatisfy { $0.allSatisfy { $0.isFaceUp } })
        #expect(game.cells.allSatisfy { $0.isEmpty })
        #expect(game.foundations.allSatisfy { $0.isEmpty })
        #expect(Set(game.tableau.flatMap { $0 }.map(\.id)).count == 52)
    }

    @Test func sameSeedSameDeal() {
        #expect(FreeCell(seed: 5) == FreeCell(seed: 5))
        #expect(FreeCell(seed: 5).tableau != FreeCell(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(FreeCell(seed: seed).hint != nil)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = FreeCell(seed: .max)
        let moved = game.move(from: .tableau(0), at: 6, to: .cell(2))
        #expect(moved)
        let decoded = try FreeCell.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }

    @Test func saveWithoutOptionsDecodesWithTheDefaults() throws {
        let game = FreeCell(seed: 3)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        object["options"] = nil
        let decoded = try FreeCell.decodeSaved(from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == game)
    }
}

@Suite struct FreeCellMoveTests {
    @Test func buildsDownInAlternatingColours() {
        let game = freeCell(columns: [[up(.spades, 8)], [up(.hearts, 7)], [up(.clubs, 7)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "builds down, not up")
    }

    @Test func anyCardGoesToAnEmptyColumn() {
        let game = freeCell(columns: [[up(.spades, 8), up(.hearts, 4)]])
        #expect(game.canMove(from: .tableau(0), at: 1, to: .tableau(3)))
    }

    @Test func freeCellsHoldOneCardEach() {
        var game = freeCell(columns: [[up(.spades, 8), up(.hearts, 4)], [up(.clubs, 2), up(.diamonds, 9)]])
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .cell(0)), "a run doesn't fit a cell")
        let moved = game.move(from: .tableau(0), at: 1, to: .cell(0))
        #expect(moved)
        #expect(!game.canMove(from: .tableau(1), at: 1, to: .cell(0)))
        #expect(game.canMove(from: .tableau(1), at: 1, to: .cell(1)))
        #expect(game.canMove(from: .cell(0), at: 0, to: .tableau(2)))
        #expect(game.moveCount == 1)
    }

    @Test func foundationsBuildUpInSuitAndKeepTheirCards() {
        let game = freeCell(foundations: [suit(.spades, upTo: 1), [], [], []], columns: [[up(.spades, 2)], [up(.hearts, 2)]])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
        #expect(!game.canMove(from: .tableau(1), at: 0, to: .foundation(0)))
        #expect(!game.canMove(from: .foundation(0), at: 0, to: .tableau(2)))
        #expect(!game.canPickUp(from: .foundation(0), at: 0))
    }

    @Test func onlyRunsMoveTogether() {
        // The 6 of clubs is not on the 7 of spades in sequence (same colour), so they can't move together.
        let game = freeCell(columns: [[up(.spades, 7), up(.clubs, 6)], [up(.hearts, 8)], [up(.hearts, 7)]])
        #expect(!game.canPickUp(from: .tableau(0), at: 0))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
        #expect(game.canMove(from: .tableau(0), at: 1, to: .tableau(2)))
    }

    @Test func runLengthDependsOnFreeCellsAndEmptyColumns() {
        #expect(FreeCell.maxMovableRun(freeCells: 4, emptyColumns: 0) == 5)
        #expect(FreeCell.maxMovableRun(freeCells: 0, emptyColumns: 1) == 2)
        #expect(FreeCell.maxMovableRun(freeCells: 2, emptyColumns: 2) == 12)

        // A run of three with one free cell and no empty column: only two cards can move.
        let run = [up(.hearts, 9), up(.spades, 8), up(.hearts, 7)]
        let filler = [up(.clubs, 1)]
        let full = [[up(.diamonds, 1)], [up(.diamonds, 2)], [up(.diamonds, 3)], []]
        let columns = [run, [up(.clubs, 10)], filler, filler, filler, filler, filler, filler]
        let blocked = FreeCell(cells: full, foundations: [[], [], [], []], tableau: columns)
        #expect(!blocked.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
        #expect(blocked.canMove(from: .tableau(0), at: 1, to: .tableau(2)) == false, "8 of spades doesn't go on an ace")

        let freed = FreeCell(cells: [[up(.diamonds, 1)], [up(.diamonds, 2)], [], []], foundations: [[], [], [], []], tableau: columns)
        #expect(freed.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
    }

    @Test func anEmptyDestinationColumnDoesNotCountForTheRun() {
        // Full cells and one empty column: two cards can move onto a card, but only one into the empty column.
        let full = [[up(.diamonds, 1)], [up(.diamonds, 2)], [up(.diamonds, 3)], [up(.diamonds, 4)]]
        let game = FreeCell(cells: full, foundations: [[], [], [], []], tableau: [
            [up(.spades, 8), up(.hearts, 7)], [up(.hearts, 9)], [up(.clubs, 1)], [up(.clubs, 1)],
            [up(.clubs, 1)], [up(.clubs, 1)], [up(.clubs, 1)], [],
        ])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .tableau(1)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(7)))
        #expect(game.canMove(from: .tableau(0), at: 1, to: .tableau(7)))
    }

    @Test func tapPrefersFoundationThenColumnThenFreeCell() {
        let game = freeCell(columns: [[up(.hearts, 1)], [up(.spades, 9), up(.hearts, 5)], [up(.clubs, 6)], [up(.diamonds, 4)]])
        #expect(game.bestDestination(from: .tableau(0), at: 0) == .foundation(0))
        #expect(game.bestDestination(from: .tableau(1), at: 1) == .tableau(2))
        #expect(game.bestDestination(from: .tableau(2), at: 0) == .cell(0))
        #expect(game.bestDestination(from: .tableau(1), at: 0) == nil, "not a run")
    }

    @Test func illegalMoveChangesNothing() {
        var game = freeCell(columns: [[up(.spades, 8)], [up(.clubs, 7)]])
        let before = game
        let changed = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!changed)
        #expect(game == before)
    }
}

@Suite struct FreeCellEndGameTests {
    @Test func wonWhenEveryCardIsOnTheFoundations() {
        var game = freeCell(
            foundations: [suit(.spades, upTo: 13), suit(.hearts, upTo: 13), suit(.diamonds, upTo: 13), suit(.clubs, upTo: 12)],
            columns: [[up(.clubs, 13)]]
        )
        #expect(!game.isWon)
        let moved = game.move(from: .tableau(0), at: 0, to: .foundation(3))
        #expect(moved)
        #expect(game.isWon)
    }

    @Test func finishesOnceEveryColumnRunsDown() {
        // Each suit alone in a column, king at the bottom; the last aces wait in the cells.
        let columns = Suit.allCases.map { suit in (2...13).reversed().map { up(suit, $0) } }
        var game = freeCell(cells: Suit.allCases.map { [up($0, 1)] }, columns: columns)
        #expect(game.canAutoComplete)
        var steps = 0
        while let move = game.nextAutoMove() {
            let changed = game.apply(move)
            #expect(changed)
            steps += 1
        }
        #expect(steps == 52)
        #expect(game.isWon)
    }

    @Test func noFinishWhileACardIsOutOfOrder() {
        let game = freeCell(columns: [[up(.spades, 2), up(.spades, 5)], [up(.spades, 1)]])
        #expect(!game.canAutoComplete)
    }
}

@Suite struct FreeCellHintTests {
    @Test func foundationMovesComeFirst() {
        let game = freeCell(cells: [[up(.hearts, 1)], [], [], []], columns: [[up(.spades, 9)], [up(.hearts, 10)]])
        #expect(game.hint == .move(Move(from: .cell(0), index: 0, to: .foundation(0))))
    }

    @Test func prefersAnEmptyColumnToACellForTheCardOverAnAce() {
        let game = freeCell(columns: [[up(.spades, 1), up(.spades, 13)], [up(.clubs, 13)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(2))))
    }

    @Test func freesABuriedAce() {
        // The 5 of hearts covers the ace of spades and fits on the 6 of clubs.
        let game = freeCell(columns: [[up(.clubs, 13), up(.diamonds, 10)], [up(.spades, 1), up(.hearts, 5)], [up(.clubs, 6)]])
        #expect(game.hint == .move(Move(from: .tableau(1), index: 1, to: .tableau(2))))
    }

    @Test func emptiesAColumn() {
        let game = freeCell(columns: [[up(.clubs, 13), up(.diamonds, 10)], [up(.spades, 9)], [up(.clubs, 13), up(.hearts, 3)]])
        #expect(game.hint == .move(Move(from: .tableau(1), index: 0, to: .tableau(0))))
    }

    @Test func usesAFreeCellWhenNoColumnTakesTheCard() {
        // Nothing takes the 9 of clubs off the 5 of hearts and the ace beneath them, so it goes to a cell.
        let game = freeCell(columns: [[up(.spades, 1), up(.hearts, 5), up(.clubs, 9)], [up(.diamonds, 13), up(.clubs, 3)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 2, to: .cell(0))))
    }

    @Test func ignoresShufflingARunBetweenColumns() {
        // The red 8 could move between the two black 9s forever; nothing else fits anywhere.
        let full = [[up(.diamonds, 13)], [up(.diamonds, 7)], [up(.hearts, 13)], [up(.hearts, 7)]]
        let game = FreeCell(cells: full, foundations: [[], [], [], []], tableau: [
            [up(.spades, 9), up(.hearts, 8)], [up(.clubs, 9)], [up(.clubs, 2)], [up(.clubs, 4)],
            [up(.spades, 1), up(.spades, 13)], [up(.clubs, 5)], [up(.spades, 4)], [up(.spades, 5)],
        ])
        #expect(!game.usefulMoves.contains(Move(from: .tableau(0), index: 1, to: .tableau(1))))
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func lastResortFreesACellOverANeededCard() {
        // Cells full; the 5 of hearts fits only on the 6 of spades, which covers the ace of clubs.
        let cells = [[up(.hearts, 5)], [up(.diamonds, 2)], [up(.diamonds, 3)], [up(.hearts, 7)]]
        let game = FreeCell(cells: cells, foundations: [[], [], [], []], tableau: [
            [up(.clubs, 1), up(.spades, 6)], [up(.spades, 10)], [up(.clubs, 10)], [up(.spades, 11)],
            [up(.clubs, 11)], [up(.spades, 12)], [up(.clubs, 12)], [up(.spades, 13)],
        ])
        #expect(game.hint == .move(Move(from: .cell(0), index: 0, to: .tableau(0))))
        #expect(!game.isStuck)
    }

    @Test func emptyingAColumnDoesNotBuryANeededCard() {
        // The 5 of hearts alone could empty its column onto the 6 of spades, but that would bury the ace.
        let game = freeCell(columns: [[up(.clubs, 1), up(.spades, 6)], [up(.hearts, 5)], [up(.diamonds, 13)]])
        #expect(!game.usefulMoves.prefix(1).contains(Move(from: .tableau(1), index: 0, to: .tableau(0))))
    }

    @Test func notStuckWhileAFreeCellCanHelp() {
        // Every column taken, all black: the king of spades over the ace can only go to a cell.
        let game = freeCell(columns: [
            [up(.spades, 1), up(.spades, 13)], [up(.clubs, 13)], [up(.spades, 12)], [up(.clubs, 12)],
            [up(.spades, 11)], [up(.clubs, 11)], [up(.spades, 10)], [up(.clubs, 10)],
        ])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .cell(0))))
        #expect(!game.isStuck)
    }
}
