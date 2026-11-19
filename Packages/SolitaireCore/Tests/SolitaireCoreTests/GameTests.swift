import Foundation
import Testing
@testable import SolitaireCore

@Suite struct CardDeckTests {
    @Test func cardIdsAreUniqueAcrossTwoDecks() {
        let ids = (0...1).flatMap { deck in Card.fullDeck.map { Card(suit: $0.suit, rank: $0.rank, deck: deck).id } }
        #expect(Set(ids).count == 104)
        #expect(Card(suit: .spades, rank: 1, deck: 1).id == 52)
        #expect(Card(suit: .clubs, rank: 13).id == 51)
    }

    @Test func saveFromBeforeTwoDecksDecodesAsDeckZero() throws {
        // A card as Sol wrote it before cards had a deck.
        let json = Data(#"{"suit":1,"rank":12,"isFaceUp":true}"#.utf8)
        let card = try JSONDecoder().decode(Card.self, from: json)
        #expect(card == Card(suit: .hearts, rank: 12, isFaceUp: true))
        #expect(card.deck == 0)
        #expect(card.id == 24)
    }

    @Test func secondDeckSurvivesCodableRoundTrip() throws {
        let card = Card(suit: .diamonds, rank: 7, isFaceUp: true, deck: 1)
        let decoded = try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card))
        #expect(decoded == card)
        let firstDeck = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Card(suit: .diamonds, rank: 7))) as? [String: Any]
        #expect(firstDeck?["deck"] == nil, "one-deck saves keep their old shape")
    }

    @Test func badRankIsAnErrorNotACrash() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Card.self, from: Data(#"{"suit":1,"rank":14,"isFaceUp":true}"#.utf8))
        }
    }
}

@Suite struct SavedGameTests {
    @Test func klondikeSaveFromBeforeTheGameProtocolStillLoads() throws {
        // Part of a Klondike save written before Sol had more than one game (and before cards had a deck).
        let json = #"""
        {"stock":[{"suit":0,"rank":2,"isFaceUp":false}],"waste":[{"suit":1,"rank":1,"isFaceUp":true}],
         "foundations":[[],[],[],[]],"tableau":[[{"suit":3,"rank":13,"isFaceUp":true}],[],[],[],[],[],[]],
         "drawCount":3,"seed":18446744073709551615,"moveCount":4}
        """#
        let game = try Klondike.decodeSaved(from: Data(json.utf8))
        #expect(game.drawCount == 3)
        #expect(game.options == KlondikeOptions(drawCount: 3))
        #expect(game.seed == .max)
        #expect(game.moveCount == 4)
        #expect(game.waste == [Card(suit: .hearts, rank: 1, isFaceUp: true)])
    }

    @Test func optionsMissingFromASaveTakeTheirDefaults() throws {
        let empty = try KlondikeOptions.decodeSaved(from: Data("{}".utf8))
        let drawThree = try KlondikeOptions.decodeSaved(from: Data(#"{"drawCount":3}"#.utf8))
        #expect(empty == KlondikeOptions())
        #expect(drawThree.drawCount == 3)
    }

    @Test func damagedKlondikeOptionsDealDrawOne() {
        #expect(Klondike(seed: 1, options: KlondikeOptions(drawCount: 2)).drawCount == 1)
        #expect(Klondike(seed: 1, options: KlondikeOptions(drawCount: 3)).drawCount == 3)
    }

    @Test func gamesCompareAcrossTypes() {
        let klondike: any SolitaireGame = Klondike(seed: 1)
        #expect(klondike.isEqual(to: Klondike(seed: 1)))
        #expect(!klondike.isEqual(to: Klondike(seed: 2)))
        #expect(!klondike.isEqual(to: FreeCell(seed: 1)))
    }

    @Test func everyKindNamesItsGame() {
        #expect(Klondike.kind == .klondike)
        #expect(FreeCell.kind == .freeCell)
        #expect(GameKind.allCases.map(\.rawValue) == ["klondike", "freecell", "yukon", "scorpion", "bakersdozen", "eightoff", "golf", "tripeaks", "pyramid"])
    }
}
