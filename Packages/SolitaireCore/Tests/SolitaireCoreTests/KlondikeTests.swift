import Foundation
import Testing
@testable import SolitaireCore

@Suite struct DealTests {
    @Test func dealsSevenColumnsWithTopCardFaceUp() {
        let game = Klondike(seed: 42)
        #expect(game.tableau.map(\.count) == [1, 2, 3, 4, 5, 6, 7])
        for column in game.tableau {
            #expect(column.last?.isFaceUp == true)
            #expect(column.dropLast().allSatisfy { !$0.isFaceUp })
        }
        #expect(game.stock.count == 24)
        #expect(game.stock.allSatisfy { !$0.isFaceUp })
        #expect(game.waste.isEmpty)
        #expect(game.foundations.allSatisfy { $0.isEmpty })
    }

    @Test func dealUsesEveryCardOnce() {
        let game = Klondike(seed: 7)
        let ids = (game.stock + game.tableau.flatMap { $0 }).map(\.id)
        #expect(Set(ids).count == 52)
    }

    @Test func sameSeedSameDeal() {
        #expect(Klondike(seed: 123) == Klondike(seed: 123))
        #expect(Klondike(seed: 123).tableau != Klondike(seed: 124).tableau)
    }
}

@Suite struct StockTests {
    @Test func drawOneTurnsOneCard() {
        var game = Klondike(seed: 1)
        let top = game.stock.last!
        let changed = game.draw()
        #expect(changed)
        #expect(game.waste.map(\.id) == [top.id])
        #expect(game.waste.last?.isFaceUp == true)
        #expect(game.stock.count == 23)
    }

    @Test func drawThreeTurnsThreeCards() {
        var game = Klondike(seed: 1, drawCount: 3)
        game.draw()
        #expect(game.waste.count == 3)
        #expect(game.stock.count == 21)
    }

    @Test func emptyStockRecyclesWasteInOriginalOrder() {
        var game = Klondike(seed: 1)
        let original = game.stock.map(\.id)
        for _ in 0..<24 { game.draw() }
        #expect(game.stock.isEmpty)
        game.draw()
        #expect(game.waste.isEmpty)
        #expect(game.stock.map(\.id) == original)
        #expect(game.stock.allSatisfy { !$0.isFaceUp })
    }

    @Test func drawWithNothingLeftDoesNothing() {
        var game = Klondike(stock: [], waste: [], foundations: [[], [], [], []], tableau: Array(repeating: [], count: 7))
        let changed = game.draw()
        #expect(!changed)
        #expect(game.moveCount == 0)
    }
}

@Suite struct MoveRuleTests {
    private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
    private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank) }
    private let noFoundations: [[Card]] = [[], [], [], []]

    private func game(tableau: [[Card]], waste: [Card] = [], foundations: [[Card]]? = nil) -> Klondike {
        var columns = tableau
        while columns.count < 7 { columns.append([]) }
        return Klondike(stock: [], waste: waste, foundations: foundations ?? noFoundations, tableau: columns)
    }

    @Test func aceGoesToEmptyFoundationOtherCardsDoNot() {
        let g = game(tableau: [[up(.hearts, 1)], [up(.hearts, 2)]])
        #expect(g.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
        #expect(!g.canMove(from: .tableau(1), at: 0, to: .foundation(0)))
    }

    @Test func foundationBuildsUpInSuit() {
        let g = game(tableau: [[up(.hearts, 2)], [up(.spades, 2)]], foundations: [[up(.hearts, 1)], [], [], []])
        #expect(g.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
        #expect(!g.canMove(from: .tableau(1), at: 0, to: .foundation(0)))
    }

    @Test func tableauBuildsDownInAlternatingColours() {
        let g = game(tableau: [[up(.spades, 8)], [up(.hearts, 7)], [up(.clubs, 7)]])
        #expect(g.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!g.canMove(from: .tableau(2), at: 0, to: .tableau(0)))
    }

    @Test func onlyKingGoesToEmptyColumn() {
        let g = game(tableau: [[], [up(.hearts, 13)], [up(.hearts, 12)]])
        #expect(g.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!g.canMove(from: .tableau(2), at: 0, to: .tableau(0)))
    }

    @Test func movingRunFlipsTheCardBeneath() {
        var g = game(tableau: [[down(.clubs, 3), up(.spades, 9), up(.hearts, 8)], [up(.diamonds, 10)]])
        let changed = g.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(changed)
        #expect(g.tableau[1].map(\.rank) == [10, 9, 8])
        #expect(g.tableau[0] == [up(.clubs, 3)])
        #expect(g.moveCount == 1)
    }

    @Test func faceDownCardsCannotMove() {
        let g = game(tableau: [[down(.hearts, 1), up(.clubs, 5)]])
        #expect(!g.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
    }

    @Test func onlyTopOfWasteMoves() {
        let g = game(tableau: [[up(.spades, 8)]], waste: [up(.hearts, 7), up(.clubs, 2)])
        #expect(!g.canMove(from: .waste, at: 0, to: .tableau(0)))
    }

    @Test func runsCannotGoToFoundation() {
        let g = game(tableau: [[up(.spades, 2), up(.hearts, 1)]], foundations: [[up(.spades, 1)], [], [], []])
        #expect(!g.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
    }

    @Test func invalidPileIndexIsRejectedNotCrashed() {
        let g = game(tableau: [[up(.hearts, 1)]])
        #expect(!g.canMove(from: .tableau(0), at: 0, to: .foundation(9)))
        #expect(!g.canMove(from: .tableau(99), at: 0, to: .foundation(0)))
    }

    @Test func bestDestinationPrefersFoundationThenColumn() {
        let g = game(tableau: [[up(.hearts, 1)], [up(.spades, 2)], [], [up(.hearts, 13)]])
        #expect(g.bestDestination(from: .tableau(0), at: 0) == .foundation(0))
        #expect(g.bestDestination(from: .tableau(3), at: 0) == nil)
    }

    @Test func illegalMoveChangesNothing() {
        var g = game(tableau: [[up(.spades, 8)], [up(.clubs, 7)]])
        let before = g
        let changed = g.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!changed)
        #expect(g == before)
    }
}

@Suite struct EndGameTests {
    /// Every card face up in the tableau, each column one suit from king down to ace.
    private func solvedTableau() -> Klondike {
        let columns = Suit.allCases.map { suit in (1...13).reversed().map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        return Klondike(stock: [], waste: [], foundations: [[], [], [], []], tableau: columns + [[], [], []])
    }

    @Test func autoCompleteFinishesTheGame() {
        var g = solvedTableau()
        #expect(g.canAutoComplete)
        var steps = 0
        while let move = g.nextAutoMove() {
            let changed = g.apply(move)
            #expect(changed)
            steps += 1
        }
        #expect(steps == 52)
        #expect(g.isWon)
        #expect(!g.canAutoComplete)
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var g = Klondike(seed: 99, drawCount: 3)
        g.draw()
        let decoded = try JSONDecoder().decode(Klondike.self, from: JSONEncoder().encode(g))
        #expect(decoded == g)
    }
}
