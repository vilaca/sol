import XCTest
@testable import Sol
@testable import SolitaireCore

/// What VoiceOver says and offers. The test host runs in English.
final class SpeechTests: XCTestCase {
    private func up(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank, isFaceUp: true) }
    private func down(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank) }

    /// Column 1: two hidden cards under the 8 of spades and 7 of hearts. Column 2: the 6 of clubs over a hidden card.
    /// Column 3: the red 9 of diamonds. The ace of hearts is on the waste.
    private var game: Klondike {
        Klondike(
            stock: [down(.spades, 2)],
            waste: [up(.hearts, 1)],
            foundations: [[], [], [], []],
            tableau: [
                [down(.clubs, 2), down(.clubs, 3), up(.spades, 8), up(.hearts, 7)],
                [down(.diamonds, 13), up(.clubs, 6)],
                [up(.diamonds, 9)],
                [], [], [], [],
            ]
        )
    }

    func testCardNames() {
        XCTAssertEqual(up(.hearts, 12).spokenName, "Queen of hearts")
        XCTAssertEqual(up(.clubs, 1).spokenName, "Ace of clubs")
        XCTAssertEqual(up(.diamonds, 7).spokenName, "7 of diamonds")
    }

    func testTableauLabelsSayWhereAndWhatIsBeneath() {
        XCTAssertEqual(Speech.label(for: up(.spades, 8), in: .tableau(0), at: 2, of: game), "Column 1, 8 of spades, 2 hidden cards, under 1 card")
        XCTAssertEqual(Speech.label(for: up(.hearts, 7), in: .tableau(0), at: 3, of: game), "Column 1, 7 of hearts")
        XCTAssertEqual(Speech.label(for: up(.diamonds, 9), in: .tableau(2), at: 0, of: game), "Column 3, 9 of diamonds")
        XCTAssertEqual(Speech.emptyLabel(.tableau(3), of: game), "Column 4, empty")
    }

    func testStockLabel() {
        XCTAssertEqual(Speech.stockLabel(game), "Draw card, 1 left")
        var drawn = game
        drawn.draw()
        XCTAssertEqual(Speech.stockLabel(drawn), "Turn the waste over")
    }

    func testOnlyLegalMovesAreOffered() {
        XCTAssertEqual(Speech.moves(from: .waste, at: 0, in: game).map(\.name), ["Move to foundation"])
        // 6 of clubs fits on the 7 of hearts in column 1 only.
        XCTAssertEqual(Speech.moves(from: .tableau(1), at: 1, in: game), [AccessibleMove(name: "Move to Column 1", destination: .tableau(0))])
        // The 8 of spades with the 7 of hearts on top fits on the red 9 in column 3.
        XCTAssertEqual(Speech.moves(from: .tableau(0), at: 2, in: game).map(\.destination), [.tableau(2)])
        XCTAssertEqual(Speech.moves(from: .tableau(2), at: 0, in: game), [])
    }

    func testMoveAnnouncementNamesTheRevealedCard() {
        let before = game
        var after = before
        XCTAssertTrue(after.move(from: .tableau(1), at: 1, to: .tableau(0)))
        XCTAssertEqual(
            Speech.moved(up(.clubs, 6), to: .tableau(0), before: before, after: after, from: .tableau(1)),
            "6 of clubs moved to Column 1, revealed King of diamonds"
        )

        var toFoundation = before
        XCTAssertTrue(toFoundation.move(from: .waste, at: 0, to: .foundation(0)))
        XCTAssertEqual(
            Speech.moved(up(.hearts, 1), to: .foundation(0), before: before, after: toFoundation, from: .waste),
            "Ace of hearts moved to foundation"
        )
    }

    func testHintText() {
        XCTAssertEqual(Speech.hint(.move(Move(from: .waste, index: 0, to: .foundation(0))), in: game), "Hint: move Ace of hearts to foundation")
        XCTAssertEqual(Speech.hint(.move(Move(from: .tableau(1), index: 1, to: .tableau(0))), in: game), "Hint: move 6 of clubs to Column 1")
        XCTAssertEqual(Speech.hint(.draw, in: game), "Hint: draw a card")
        XCTAssertEqual(Speech.hint(nil, in: game), "No moves left")
    }

    func testDrawAnnouncement() {
        var drawn = game
        drawn.draw()
        XCTAssertEqual(Speech.drew(drawn), "Drew 2 of spades")
    }
}
