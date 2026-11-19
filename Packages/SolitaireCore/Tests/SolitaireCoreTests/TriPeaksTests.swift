import Foundation
import Testing
@testable import SolitaireCore

private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank) }

/// A position with only the given cards in the peaks.
private func triPeaks(
    waste: [Card], cards: [Int: Card], stock: [Card] = [], options: TriPeaksOptions = TriPeaksOptions()
) -> TriPeaks {
    TriPeaks(stock: stock, waste: waste, tableau: (0..<28).map { cards[$0].map { [$0] } ?? [] }, options: options)
}

@Suite struct TriPeaksDealTests {
    @Test func dealsThreePeaksWithTheBottomRowFaceUp() {
        let game = TriPeaks(seed: 42)
        #expect(game.tableau.count == 28 && game.tableau.allSatisfy { $0.count == 1 })
        #expect(game.tableau[18...].allSatisfy { $0[0].isFaceUp })
        #expect(game.tableau[..<18].allSatisfy { !$0[0].isFaceUp })
        #expect(game.waste.count == 1 && game.waste[0].isFaceUp)
        #expect(game.stock.count == 23 && game.stock.allSatisfy { !$0.isFaceUp })
        let ids = (game.tableau.flatMap { $0 } + game.waste + game.stock).map(\.id)
        #expect(Set(ids).count == 52)
        #expect(game.options.wrapsKingAndAce)
    }

    @Test func sameSeedSameDeal() {
        #expect(TriPeaks(seed: 5) == TriPeaks(seed: 5))
        #expect(TriPeaks(seed: 5).tableau != TriPeaks(seed: 6).tableau)
    }

    @Test func freshDealsHaveMoves() {
        for seed in UInt64(0)..<50 {
            #expect(TriPeaks(seed: seed).hint != nil)
            #expect(!TriPeaks(seed: seed).isStuck)
        }
    }

    @Test func gameSurvivesCodableRoundTrip() throws {
        var game = TriPeaks(seed: .max)
        game.draw()
        let decoded = try TriPeaks.decodeSaved(from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }

    @Test func saveWithoutOptionsDecodesWithTheDefaults() throws {
        let game = TriPeaks(seed: 3)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        object["options"] = nil
        let decoded = try TriPeaks.decodeSaved(from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == game)
        #expect(decoded.options.wrapsKingAndAce)
    }
}

@Suite struct TriPeaksLayoutTests {
    @Test func rowsAndPeaks() {
        #expect([0, 2, 3, 8, 9, 17, 18, 27].map(TriPeaks.row(of:)) == [0, 0, 1, 1, 2, 2, 3, 3])
        #expect([0, 1, 2].map(TriPeaks.peak(of:)) == [0, 1, 2])
        #expect([3, 4, 5, 6, 7, 8].map(TriPeaks.peak(of:)) == [0, 0, 1, 1, 2, 2])
        #expect([9, 11, 12, 14, 15, 17].map(TriPeaks.peak(of:)) == [0, 0, 1, 1, 2, 2])
        #expect([18, 20, 21, 23, 24, 27].map(TriPeaks.peak(of:)) == [0, 0, 1, 1, 2, 2])
    }

    @Test func coordinates() {
        #expect(TriPeaks.coordinates(of: 0).x == 1.5)
        #expect(TriPeaks.coordinates(of: 2).x == 7.5)
        #expect(TriPeaks.coordinates(of: 3).x == 1 && TriPeaks.coordinates(of: 4).x == 2)
        #expect(TriPeaks.coordinates(of: 5).x == 4 && TriPeaks.coordinates(of: 8).x == 8)
        #expect(TriPeaks.coordinates(of: 9).x == 0.5 && TriPeaks.coordinates(of: 17).x == 8.5)
        #expect((18..<28).map { TriPeaks.coordinates(of: $0).x } == (0..<10).map(Double.init))
    }

    @Test func everyCardSitsBetweenTheTwoThatOverlapIt() {
        for position in 0..<18 {
            let covering = TriPeaks.coveringPositions(of: position)
            #expect(covering.count == 2)
            let middle = covering.map { TriPeaks.coordinates(of: $0).x }.reduce(0, +) / 2
            #expect(TriPeaks.coordinates(of: position).x == middle, "position \(position)")
            #expect(covering.allSatisfy { TriPeaks.row(of: $0) == TriPeaks.row(of: position) + 1 })
        }
        #expect((18..<28).allSatisfy { TriPeaks.coveringPositions(of: $0).isEmpty })
        #expect(TriPeaks.coveringPositions(of: 0) == [3, 4])
        #expect(TriPeaks.coveringPositions(of: 4) == [10, 11])
        #expect(TriPeaks.coveringPositions(of: 17) == [26, 27])
    }
}

@Suite struct TriPeaksMoveTests {
    @Test func onlyFreeCardsPlay() {
        let game = TriPeaks(seed: 42)
        for position in 0..<18 {
            #expect(!game.canPickUp(from: .tableau(position), at: 0))
            #expect(!game.isFree(position))
        }
        for position in 18..<28 { #expect(game.isFree(position)) }
    }

    @Test func playsOneRankAboveOrBelowTheWaste() {
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 6), 19: up(.spades, 8), 20: up(.spades, 9), 21: up(.spades, 7)])
        #expect(game.canMove(from: .tableau(18), at: 0, to: .waste))
        #expect(game.canMove(from: .tableau(19), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(20), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(21), at: 0, to: .waste))
        #expect(game.bestDestination(from: .tableau(18), at: 0) == .waste)
        #expect(game.bestDestination(from: .tableau(20), at: 0) == nil)
    }

    @Test func aCoveredCardCannotPlayEvenWhenItFits() {
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [9: up(.spades, 6), 18: up(.spades, 2), 19: up(.spades, 2)])
        #expect(!game.canMove(from: .tableau(9), at: 0, to: .waste))
    }

    @Test func playingBothCoveringCardsTurnsTheCardAboveFaceUp() {
        var game = triPeaks(waste: [up(.hearts, 7)], cards: [9: down(.clubs, 2), 18: up(.spades, 6), 19: up(.spades, 5)])
        let first = game.move(from: .tableau(18), at: 0, to: .waste)
        #expect(first)
        #expect(!game.tableau[9][0].isFaceUp, "still covered by position 19")
        #expect(!game.isFree(9))
        let second = game.move(from: .tableau(19), at: 0, to: .waste)
        #expect(second)
        #expect(game.tableau[9][0].isFaceUp)
        #expect(game.isFree(9))
        #expect(game.moveCount == 2)
    }

    @Test func illegalMoveChangesNothing() {
        var game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 2), 9: down(.clubs, 6)])
        let before = game
        let far = game.move(from: .tableau(18), at: 0, to: .waste)
        #expect(!far)
        let hidden = game.move(from: .tableau(9), at: 0, to: .waste)
        #expect(!hidden)
        let toPeak = game.move(from: .tableau(18), at: 0, to: .tableau(19))
        #expect(!toPeak)
        #expect(game == before)
    }

    @Test func badPileIndexesDoNotTrap() {
        let game = TriPeaks(seed: 1)
        #expect(!game.canMove(from: .tableau(99), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(-1), at: 0, to: .waste))
        #expect(!game.canMove(from: .tableau(20), at: 5, to: .waste))
        #expect(game.cards(in: .tableau(99)).isEmpty)
        #expect(!game.isFree(99))
    }

    @Test func drawTurnsTheNextCardOntoTheWasteAndNeverRedeals() {
        var game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 2)], stock: [down(.clubs, 3)])
        let first = game.draw()
        #expect(first)
        #expect(game.waste.last == up(.clubs, 3))
        let second = game.draw()
        #expect(!second)
        #expect(game.moveCount == 1)
        #expect(!TriPeaks.recyclesWaste)
    }

    @Test func winsWhenEveryPeakIsClear() {
        var game = triPeaks(waste: [up(.hearts, 7)], cards: [27: up(.spades, 6)])
        #expect(!game.isWon)
        game.move(from: .tableau(27), at: 0, to: .waste)
        #expect(game.isWon)
        #expect(!game.isStuck)
    }
}

@Suite struct TriPeaksOptionTests {
    @Test func wrapsKingAndAceByDefault() {
        let onAce = triPeaks(waste: [up(.hearts, 1)], cards: [18: up(.spades, 13)])
        #expect(onAce.canMove(from: .tableau(18), at: 0, to: .waste))
        let onKing = triPeaks(waste: [up(.hearts, 13)], cards: [18: up(.spades, 1)])
        #expect(onKing.canMove(from: .tableau(18), at: 0, to: .waste))
    }

    @Test func wrapCanBeSwitchedOff() {
        var options = TriPeaksOptions()
        options.wrapsKingAndAce = false
        let onAce = triPeaks(waste: [up(.hearts, 1)], cards: [18: up(.spades, 13)], options: options)
        #expect(!onAce.canMove(from: .tableau(18), at: 0, to: .waste))
        let onKing = triPeaks(waste: [up(.hearts, 13)], cards: [18: up(.spades, 1)], options: options)
        #expect(!onKing.canMove(from: .tableau(18), at: 0, to: .waste))
    }
}

@Suite struct TriPeaksHintTests {
    @Test func prefersThePlayThatClearsTheMostCards() {
        // Position 18's 8 leads nowhere; 20's 6 is followed by 21's 5 and 22's 4.
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 8), 20: up(.spades, 6), 21: up(.clubs, 5), 22: up(.clubs, 4)])
        #expect(game.hint == .move(Move(from: .tableau(20), index: 0, to: .waste)))
    }

    @Test func whenChainsTieItTurnsUpACard() {
        // Both plays clear one card. Only the 8 at 27 uncovers the face-down card at 17 (26 is empty).
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [17: down(.clubs, 2), 18: up(.spades, 6), 27: up(.spades, 8)])
        #expect(game.usefulMoves.first == Move(from: .tableau(27), index: 0, to: .waste))
        #expect(game.usefulMoves.count == 2)
    }

    @Test func movesComeBeforeDrawing() {
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 6)], stock: [down(.clubs, 3)])
        #expect(game.hint == .move(Move(from: .tableau(18), index: 0, to: .waste)))
    }

    @Test func drawsWhenNoCardFits() {
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 2)], stock: [down(.clubs, 3)])
        #expect(game.hint == .draw)
        #expect(!game.isStuck)
    }

    @Test func stuckWhenNothingFitsAndTheStockIsEmpty() {
        let game = triPeaks(waste: [up(.hearts, 7)], cards: [18: up(.spades, 2)])
        #expect(game.hint == nil)
        #expect(game.isStuck)
    }

    @Test func followingTheHintNeverLoops() {
        for seed in UInt64(0)..<20 {
            var game = TriPeaks(seed: seed)
            var steps = 0
            while let hint = game.hint, steps < 200 {
                switch hint {
                case .move(let move): game.apply(move)
                case .draw: game.draw()
                }
                steps += 1
            }
            #expect(steps < 200)
            #expect(game.isWon || game.isStuck)
        }
    }
}
