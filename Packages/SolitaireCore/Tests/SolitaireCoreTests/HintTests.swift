import Testing
@testable import SolitaireCore

@Suite struct HintTests {
    private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
    private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank) }

    private func game(stock: [Card] = [], waste: [Card] = [], foundations: [[Card]] = [[], [], [], []], columns: [[Card]], drawCount: Int = 1) -> Klondike {
        Klondike(stock: stock, waste: waste, foundations: foundations, tableau: columns + Array(repeating: [], count: 7 - columns.count), drawCount: drawCount)
    }

    @Test func foundationMovesComeFirst() {
        let g = game(waste: [up(.hearts, 1)], columns: [[down(.clubs, 5), up(.spades, 9)], [up(.hearts, 10)]])
        #expect(g.hint == .move(Move(from: .waste, index: 0, to: .foundation(0))))
    }

    @Test func suggestsTheMoveThatUncoversACard() {
        // The 9 of spades on a hidden card fits on the 10 of hearts; the 8 of diamonds is already alone.
        let g = game(columns: [[down(.clubs, 5), up(.spades, 9)], [up(.hearts, 10)], [up(.diamonds, 8)]])
        #expect(g.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
    }

    @Test func ignoresShufflingBetweenColumns() {
        // The red 8 could move between the two black 9s forever without uncovering anything.
        let g = game(columns: [[up(.spades, 9), up(.hearts, 8)], [up(.clubs, 9)]])
        #expect(g.usefulMoves.isEmpty)
        #expect(g.hint == nil)
    }

    @Test func freesACardForAFoundation() {
        // Moving the 6 of hearts off the ace of clubs lets the ace go up.
        let g = game(columns: [[up(.clubs, 1), up(.hearts, 6)], [up(.spades, 7)]])
        #expect(g.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
    }

    @Test func drawsWhenOnlyTheStockCanHelp() {
        // Deep in the stock is the ace of hearts.
        let g = game(stock: [up(.hearts, 1), down(.clubs, 9), down(.clubs, 10)], columns: [[up(.spades, 13)]])
        #expect(g.hint == .draw)
    }

    @Test func turnsTheWasteOverWhenACardInItCanBePlayed() {
        let g = game(waste: [up(.hearts, 1), up(.clubs, 9)], columns: [[up(.spades, 13)]])
        #expect(g.hint == .draw)
    }

    @Test func stuckWhenNothingInTheStockFits() {
        let g = game(stock: [down(.clubs, 9), down(.diamonds, 4)], waste: [up(.clubs, 10)], columns: [[up(.spades, 13)], [down(.hearts, 1), up(.hearts, 3)]])
        #expect(g.hint == nil)
    }

    @Test func drawThreeOnlySeesEveryThirdCard() {
        // With draw 3 and no plays, the ace (second from the top of the stock) never comes up on the waste.
        let stock = [down(.clubs, 9), down(.hearts, 1), down(.diamonds, 4)]
        #expect(game(stock: stock, columns: [[up(.spades, 13)]], drawCount: 3).hint == nil)
        #expect(game(stock: stock, columns: [[up(.spades, 13)]], drawCount: 1).hint == .draw)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(Klondike(seed: seed).hint != nil)
        }
    }
}
