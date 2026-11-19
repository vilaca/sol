import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: false) }

private func spider(stock: [Card] = [], foundations: [[Card]] = Array(repeating: [], count: 8), columns: [[Card]]) -> Spider {
    Spider(stock: stock, foundations: foundations, tableau: columns + Array(repeating: [], count: 10 - columns.count))
}

/// A suit from `high` down to `low`.
private func run(_ suit: Suit, from high: Int = 13, to low: Int) -> [Card] {
    stride(from: high, through: low, by: -1).map { up(suit, $0) }
}

private func fullSuit(_ suit: Suit) -> [Card] { (1...13).map { up(suit, $0) } }

/// Ten cards for a stock row, none of which completes anything.
private func row(_ rank: Int = 2) -> [Card] { Array(repeating: down(.hearts, rank), count: 10) }

@Suite struct SpiderDealTests {
    @Test func dealsTenColumnsAndAStockOfFifty() {
        let game = Spider(seed: 42)
        #expect(game.tableau.map(\.count) == [6, 6, 6, 6, 5, 5, 5, 5, 5, 5])
        for column in game.tableau {
            #expect(column.dropLast().allSatisfy { !$0.isFaceUp })
            #expect(column.last?.isFaceUp == true)
        }
        #expect(game.stock.count == 50)
        #expect(game.stock.allSatisfy { !$0.isFaceUp })
        #expect(game.foundations.count == 8 && game.foundations.allSatisfy { $0.isEmpty })
        #expect(game.moveCount == 0)
        #expect(!game.isWon)
    }

    @Test func everyDealHasA104DistinctCards() {
        for suits in [1, 2, 4] {
            var options = SpiderOptions()
            options.suits = suits
            let game = Spider(seed: 42, options: options)
            let cards = game.tableau.flatMap { $0 } + game.stock
            #expect(Set(cards.map(\.id)).count == 104, "\(suits) suits")
        }
    }

    @Test func suitsOptionDecidesWhichSuitsAreDealt() {
        func suits(_ count: Int) -> [Suit: Int] {
            var options = SpiderOptions()
            options.suits = count
            let game = Spider(seed: 7, options: options)
            return Dictionary(grouping: game.tableau.flatMap { $0 } + game.stock, by: \.suit).mapValues(\.count)
        }
        #expect(suits(1) == [.spades: 104])
        #expect(suits(2) == [.spades: 52, .hearts: 52])
        #expect(suits(4) == [.spades: 26, .hearts: 26, .diamonds: 26, .clubs: 26])
        #expect(suits(3) == [.spades: 104], "anything else is one suit")
        #expect(SpiderOptions().suits == 1)
    }

    @Test func sameSeedSameDeal() {
        #expect(Spider(seed: 5) == Spider(seed: 5))
        #expect(Spider(seed: 5).tableau != Spider(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for suits in [1, 2, 4] {
            var options = SpiderOptions()
            options.suits = suits
            for seed in UInt64(0)..<50 {
                let game = Spider(seed: seed, options: options)
                #expect(game.hint != nil)
                #expect(!game.isStuck)
            }
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var options = SpiderOptions()
        options.suits = 4
        var game = Spider(seed: .max, options: options)
        let dealt = game.draw()
        #expect(dealt)
        let decoded = try Spider.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
        #expect(decoded.options.suits == 4)
    }

    @Test func savedGameWithoutOptionsDecodesWithTheDefault() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Spider(seed: 1))) as? [String: Any])
        object["options"] = [String: Any]()
        let decoded = try Spider.decodeSaved(from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.options.suits == 1)
    }
}

@Suite struct SpiderMoveTests {
    @Test func buildsDownInAnySuit() {
        let game = spider(columns: [[up(.spades, 8)], [up(.hearts, 7)], [up(.spades, 6)]])
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(1)), "builds down, not up")
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(0)), "not one rank apart")
    }

    @Test func onlyARunOfOneSuitMovesTogether() {
        let game = spider(columns: [
            [up(.spades, 9), up(.spades, 8), up(.spades, 7)],
            [up(.spades, 9), up(.hearts, 8), up(.spades, 7)],
            [up(.spades, 10)],
        ])
        #expect(game.canPickUp(from: .tableau(0), at: 0))
        #expect(game.canMove(from: .tableau(0), at: 0, to: .tableau(2)), "the whole suited run")
        #expect(!game.canPickUp(from: .tableau(1), at: 0), "8 of hearts breaks the run")
        #expect(!game.canPickUp(from: .tableau(1), at: 1))
        #expect(game.canPickUp(from: .tableau(1), at: 2))
    }

    @Test func movesTheRunAndCountsOneMove() {
        var game = spider(columns: [[up(.hearts, 9), up(.spades, 8), up(.spades, 7)], [up(.clubs, 9)]])
        let ok = game.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(ok)
        #expect(game.tableau[1].map(\.rank) == [9, 8, 7])
        #expect(game.tableau[0].map(\.rank) == [9])
        #expect(game.moveCount == 1)
    }

    @Test func faceDownCardsCannotMoveAndTurnUpWhenUncovered() {
        var game = spider(columns: [[down(.clubs, 5), up(.hearts, 7)], [up(.hearts, 8)], [down(.spades, 2)]])
        #expect(!game.canMove(from: .tableau(2), at: 0, to: .tableau(1)))
        let ok = game.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(ok)
        #expect(game.tableau[0].map(\.isFaceUp) == [true])
    }

    @Test func emptyColumnTakesAnyCardOrRun() {
        let game = spider(columns: [[up(.spades, 9), up(.spades, 8)], [up(.clubs, 3)], []])
        #expect(game.canMove(from: .tableau(0), at: 0, to: .tableau(2)))
        #expect(game.canMove(from: .tableau(0), at: 1, to: .tableau(2)))
        #expect(game.canMove(from: .tableau(1), at: 0, to: .tableau(2)))
    }

    @Test func illegalMoveChangesNothing() {
        var game = spider(columns: [[up(.spades, 8)], [up(.hearts, 5)]])
        let before = game
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(!ok)
        #expect(game == before)
        #expect(!game.canMove(from: .tableau(9), at: 0, to: .tableau(0)))
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .tableau(10)))
        #expect(!game.canMove(from: .tableau(0), at: 3, to: .tableau(1)))
        #expect(!game.canMove(from: .tableau(0), at: -1, to: .tableau(1)))
        #expect(!game.canMove(from: .foundation(0), at: 0, to: .tableau(1)))
        #expect(game.cards(in: .tableau(10)).isEmpty)
        #expect(game.cards(in: .foundation(8)).isEmpty)
    }

    @Test func cardsCannotBeMovedToAFoundationByHand() {
        let game = spider(columns: [[up(.spades, 1)]])
        #expect(!game.canMove(from: .tableau(0), at: 0, to: .foundation(0)))
    }

    @Test func stockDealsOneCardOntoEveryColumn() {
        var game = spider(stock: row(2) + row(3), columns: Array(repeating: [up(.spades, 9)], count: 10))
        let dealt = game.draw()
        #expect(dealt)
        #expect(game.stock.count == 10)
        #expect(game.tableau.allSatisfy { $0.count == 2 && $0.last?.isFaceUp == true && $0.last?.rank == 3 })
        #expect(game.moveCount == 1)
    }

    @Test func stockCannotBeDealtWhileAColumnIsEmpty() {
        var game = spider(stock: row(), columns: Array(repeating: [up(.spades, 9)], count: 9))
        let before = game
        #expect(!game.canDeal)
        let dealt = game.draw()
        #expect(!dealt)
        #expect(game == before)
    }

    @Test func emptyStockDealsNothing() {
        var game = spider(columns: Array(repeating: [up(.spades, 9)], count: 10))
        let dealt = game.draw()
        #expect(!dealt)
        #expect(game.moveCount == 0)
    }

    @Test func aCompleteRunLeavesForAFoundationAtOnce() {
        var game = spider(columns: [[down(.hearts, 5), up(.spades, 1)], run(.spades, to: 2)])
        let ok = game.move(from: .tableau(0), at: 1, to: .tableau(1))
        #expect(ok)
        #expect(game.tableau[1].isEmpty)
        #expect(game.foundations[0].map(\.rank) == Array((1...13).reversed()))
        #expect(game.tableau[0].map(\.isFaceUp) == [true], "the card it uncovered turns up")
        #expect(game.moveCount == 1, "one undo step")
    }

    @Test func aRunDealtFromTheStockLeavesToo() {
        var game = spider(stock: Array(repeating: down(.hearts, 2), count: 9) + [down(.spades, 1)], columns: [run(.spades, to: 2)] + Array(repeating: [up(.clubs, 9)], count: 9))
        let dealt = game.draw()
        #expect(dealt)
        #expect(game.foundations.filter { !$0.isEmpty }.count == 1)
        #expect(game.tableau[0].isEmpty)
    }

    @Test func aRunOfMixedSuitsStays() {
        var game = spider(columns: [run(.spades, from: 13, to: 2).enumerated().map { $0.offset == 5 ? up(.hearts, $0.element.rank) : $0.element }, [up(.spades, 1)]])
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(ok)
        #expect(game.tableau[0].count == 13)
        #expect(game.foundations.allSatisfy { $0.isEmpty })
    }

    @Test func aRunThatDoesNotStartWithAKingStays() {
        var game = spider(columns: [run(.spades, from: 12, to: 2), [up(.spades, 1)]])
        let ok = game.move(from: .tableau(1), at: 0, to: .tableau(0))
        #expect(ok)
        #expect(game.tableau[0].count == 12)
        #expect(game.foundations.allSatisfy { $0.isEmpty })
    }

    @Test func winsWhenEightRunsAreOut() {
        var game = spider(
            foundations: [fullSuit(.spades), fullSuit(.spades), fullSuit(.spades), fullSuit(.spades), fullSuit(.spades), fullSuit(.spades), fullSuit(.spades), []],
            columns: [[up(.spades, 1)], run(.spades, to: 2)]
        )
        #expect(!game.isWon)
        let ok = game.move(from: .tableau(0), at: 0, to: .tableau(1))
        #expect(ok)
        #expect(game.isWon)
    }

    @Test func tapGoesToTheSameSuitFirst() {
        let game = spider(columns: [[up(.hearts, 8)], [up(.spades, 8)], [up(.spades, 7)], [up(.clubs, 3)], []])
        #expect(game.bestDestination(from: .tableau(2), at: 0) == .tableau(1))
        #expect(game.bestDestination(from: .tableau(3), at: 0) == nil, "nothing to join, and it already is at the bottom")
        let covered = spider(columns: [[up(.hearts, 9), up(.clubs, 3)], []])
        #expect(covered.bestDestination(from: .tableau(0), at: 1) == .tableau(1))
    }
}

@Suite struct SpiderHintTests {
    @Test func aMoveThatCompletesARunComesFirst() {
        let game = spider(columns: [[down(.hearts, 5), up(.clubs, 9)], [up(.hearts, 6)], run(.spades, to: 2), [up(.spades, 1)]])
        #expect(game.hint == .move(Move(from: .tableau(3), index: 0, to: .tableau(2))))
    }

    @Test func turningUpACardBeatsOtherMoves() {
        let game = spider(columns: [
            [down(.clubs, 5), up(.hearts, 7)], [up(.hearts, 8)],
            [up(.spades, 9)], [up(.spades, 8), up(.spades, 7)],
        ])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(1))))
    }

    @Test func uncoveringOntoTheSameSuitComesBeforeOtherSuits() {
        let game = spider(columns: [[down(.clubs, 5), up(.hearts, 7)], [up(.spades, 8)], [up(.hearts, 8)]])
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(2))))
    }

    @Test func prefersTheColumnWithMostHiddenCards() {
        let game = spider(columns: [
            [down(.clubs, 5), up(.hearts, 7)],
            [down(.clubs, 6), down(.clubs, 9), down(.clubs, 10), up(.spades, 7)],
            [up(.hearts, 8)], [up(.spades, 8)],
        ])
        #expect(game.hint == .move(Move(from: .tableau(1), index: 3, to: .tableau(3))))
    }

    @Test func joiningTheSameSuitIsUsefulButSplittingIsNot() {
        let game = spider(columns: [[up(.spades, 9), up(.spades, 8)], [up(.hearts, 9), up(.clubs, 5)], [up(.hearts, 8)]])
        // The 8 of hearts goes onto the 9 of hearts only if that 9 is a top card: here it isn't.
        #expect(game.usefulMoves.isEmpty)
        let open = spider(columns: [[up(.spades, 9), up(.spades, 8)], [up(.hearts, 9)], [up(.hearts, 8), up(.hearts, 7)]])
        #expect(!open.usefulMoves.contains(Move(from: .tableau(0), index: 1, to: .tableau(1))), "would split the suited pair")
        #expect(open.usefulMoves == [Move(from: .tableau(2), index: 0, to: .tableau(1))], "the whole suited run joins its suit")
    }

    @Test func aWholeColumnOnAnotherSuitOnlyHelpsOnceTheStockIsEmpty() {
        let columns = [[up(.spades, 9)], [up(.hearts, 8)]]
        #expect(spider(stock: row(), columns: columns).usefulMoves.isEmpty)
        #expect(spider(columns: columns).usefulMoves == [Move(from: .tableau(1), index: 0, to: .tableau(0))])
    }

    @Test func aFullBoardWithNoMovesHintsTheStock() {
        let game = spider(stock: row(), columns: (0..<10).map { [up(.clubs, $0 % 2 == 0 ? 13 : 5)] })
        #expect(game.usefulMoves.isEmpty)
        #expect(game.hint == .draw)
        #expect(!game.isStuck)
    }

    @Test func anEmptyColumnBlocksTheStockSoTheHintFillsIt() {
        // Two cards in column 0; nothing joins. Column 9 is empty, so the stock can't be dealt until it is filled.
        let game = spider(stock: row(), columns: [[up(.clubs, 5), up(.clubs, 12)]] + (1..<9).map { _ in [up(.clubs, 5)] })
        #expect(game.usefulMoves.isEmpty)
        #expect(game.hint == .move(Move(from: .tableau(0), index: 1, to: .tableau(9))))
        var after = game
        after.apply(Move(from: .tableau(0), index: 1, to: .tableau(9)))
        #expect(after.hint == .draw)
    }

    @Test func stuckWithAnEmptyStockAndNoMoves() {
        let game = spider(columns: [[up(.hearts, 9)], [up(.spades, 5)]])
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func stuckWhenColumnsAreEmptyAndEveryColumnHasOneCard() {
        let game = spider(stock: row(), columns: [[up(.hearts, 9)], [up(.spades, 5)]])
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func followingTheHintNeverLoops() {
        for suits in [1, 2, 4] {
            var options = SpiderOptions()
            options.suits = suits
            for seed in UInt64(0)..<20 {
                var game = Spider(seed: seed, options: options)
                var steps = 0
                while let hint = game.hint, !game.isWon, steps < 1500 {
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
                #expect(steps < 1500, "\(suits) suits, seed \(seed)")
            }
        }
    }

    @Test func oneSuitDealsAreOftenWonByTheHint() {
        var won = 0
        for seed in UInt64(0)..<20 {
            var game = Spider(seed: seed)
            var steps = 0
            while let hint = game.hint, !game.isWon, steps < 1500 {
                switch hint {
                case .move(let move): game.apply(move)
                case .draw: game.draw()
                }
                steps += 1
            }
            if game.isWon { won += 1 }
        }
        #expect(won >= 1, "the hint plays one-suit Spider well enough to win some deals")
    }
}
