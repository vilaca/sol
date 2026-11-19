import XCTest
@testable import Sol
@testable import SolitaireCore

/// Several games side by side: the New menu, one saved game per game, options and statistics per game.
@MainActor
final class GamesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "GamesTests"

    private let drawOne = GameChoice(kind: .klondike, variant: ["draw": 0])
    private let drawThree = GameChoice(kind: .klondike, variant: ["draw": 1])
    private let freeCell = GameChoice(kind: .freeCell, variant: [:])

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeModel(seed: UInt64? = 42) -> GameModel {
        GameModel(launch: LaunchOptions(seed: seed), defaults: defaults)
    }

    private func relaunch() -> GameModel {
        GameModel(defaults: defaults)
    }

    // MARK: - New menu

    func testNewMenuListsEveryGameAndVariant() {
        XCTAssertEqual(GameChoice.all.map(\.id), ["new-klondike.draw-1", "new-klondike.draw-3", "new-freecell", "new-yukon", "new-scorpion", "new-bakersdozen", "new-eightoff"])
        XCTAssertEqual(GameChoice.all.map(\.title), ["Klondike – Draw 1", "Klondike – Draw 3", "FreeCell", "Yukon", "Scorpion", "Baker's Dozen", "Eight Off"])
    }

    func testStatisticsKeysNameTheGameAndItsOptions() {
        XCTAssertEqual(AnyGame(Klondike(seed: 1)).statisticsKey, "klondike.draw-1")
        XCTAssertEqual(AnyGame(Klondike(seed: 1, drawCount: 3)).statisticsKey, "klondike.draw-3")
        XCTAssertEqual(AnyGame(FreeCell(seed: 1)).statisticsKey, "freecell")
        XCTAssertEqual(AnyGame(Yukon(seed: 1)).statisticsKey, "yukon")
        XCTAssertEqual(AnyGame(Scorpion(seed: 1)).statisticsKey, "scorpion")
        XCTAssertEqual(AnyGame(BakersDozen(seed: 1)).statisticsKey, "bakersdozen")
        XCTAssertEqual(AnyGame(EightOff(seed: 1)).statisticsKey, "eightoff.empty-kings")
        var anyCard = EightOffOptions()
        anyCard.anyCardInEmptyColumn = true
        XCTAssertEqual(AnyGame(EightOff(seed: 1, options: anyCard)).statisticsKey, "eightoff.empty-any")
        XCTAssertEqual(EightOff.title(for: anyCard), "Eight Off – Empty columns: Any card")
        XCTAssertEqual(Klondike.title(for: KlondikeOptions(drawCount: 3)), "Klondike – Draw 3")
    }

    // MARK: - One saved game per game

    func testSwitchingGamesKeepsEachGameSaved() {
        let model = makeModel()
        model.draw()
        let klondike = model.game
        model.newGame(freeCell)
        XCTAssertEqual(model.kind, .freeCell)
        XCTAssertEqual(model.statistics, Statistics(), "leaving a game is not a loss")
        XCTAssertFalse(model.isInProgress)

        let card = model.game.cards(in: .tableau(0)).count - 1
        XCTAssertTrue(model.move(from: .tableau(0), at: card, to: .cell(0)))
        let freeCellGame = model.game
        XCTAssertEqual(relaunch().game, freeCellGame, "the last game played comes back on launch")

        XCTAssertFalse(model.abandons(drawOne), "the saved Klondike game is draw 1: it resumes")
        model.newGame(drawOne)
        XCTAssertEqual(model.game, klondike)
        XCTAssertTrue(model.isInProgress)
        model.newGame(freeCell)
        XCTAssertEqual(model.game, freeCellGame)
    }

    func testOtherVariantAbandonsTheSavedGame() {
        let model = makeModel()
        model.draw()
        model.newGame(freeCell)
        XCTAssertTrue(model.abandons(drawThree), "the saved game is draw 1, so draw 3 deals a new one")
        model.newGame(drawThree)
        XCTAssertEqual(model.game.drawCount, 3)
        XCTAssertEqual(model.game.moveCount, 0)
        XCTAssertEqual(model.statistics["klondike.draw-1"].played, 1)
        XCTAssertEqual(model.statistics["klondike.draw-3"].played, 0)
    }

    func testUnstartedGamesAreNotAbandoned() {
        let model = makeModel()
        XCTAssertFalse(model.abandons(drawThree))
        XCTAssertFalse(model.abandons(freeCell))
        model.draw()
        XCTAssertTrue(model.abandons(drawThree))
        XCTAssertTrue(model.abandons(drawOne), "dealing the game in play again gives it up")
    }

    func testExistingKlondikeSaveStillLoads() throws {
        // As Sol saved it before it had other games: the game under "savedGame", no "currentGame".
        var game = Klondike(seed: .max, drawCount: 3)
        game.draw()
        defaults.set(try JSONEncoder().encode(game), forKey: "savedGame")
        XCTAssertEqual(relaunch().game, AnyGame(game))
    }

    // MARK: - Options

    func testRunningGameKeepsTheOptionsItWasDealtWith() {
        let model = makeModel()
        model.draw()
        model.setPreferredOptions(KlondikeOptions(drawCount: 3), for: .klondike)
        XCTAssertEqual(model.game.drawCount, 1)
        XCTAssertEqual(relaunch().game.drawCount, 1, "saved with the game")
        model.newGame()
        XCTAssertEqual(model.game.drawCount, 3)
        XCTAssertEqual(model.statistics["klondike.draw-1"].played, 1, "counted under the options it was dealt with")
        XCTAssertEqual((relaunch().preferredOptions(for: .klondike) as? KlondikeOptions)?.drawCount, 3)
    }

    func testOldDrawCountSettingBecomesKlondikeOptions() {
        defaults.set(3, forKey: "drawCount")
        XCTAssertEqual((relaunch().preferredOptions(for: .klondike) as? KlondikeOptions)?.drawCount, 3)
    }

    func testRuleSettingReadsAndWritesOptions() throws {
        let deal = try XCTUnwrap(Klondike.ruleSettings.first)
        XCTAssertEqual(deal.choice(in: KlondikeOptions(drawCount: 3)), 1)
        let options = deal.setting(0, in: KlondikeOptions(drawCount: 3)) as? KlondikeOptions
        XCTAssertEqual(options?.drawCount, 1)
        XCTAssertTrue(FreeCell.ruleSettings.isEmpty)
    }

    // MARK: - Statistics

    func testStatisticsFromBeforeOtherGamesSurvive() throws {
        let json = #"{"drawOne":{"played":5,"won":2,"currentStreak":1,"bestStreak":2,"bestTime":95,"fewestMoves":88},"#
            + #""drawThree":{"played":1,"won":0,"currentStreak":0,"bestStreak":0}}"#
        defaults.set(Data(json.utf8), forKey: "statistics")
        let stats = relaunch().statistics
        XCTAssertEqual(stats["klondike.draw-1"], ModeStatistics(played: 5, won: 2, currentStreak: 1, bestStreak: 2, bestTime: 95, fewestMoves: 88))
        XCTAssertEqual(stats["klondike.draw-3"].played, 1)
        XCTAssertEqual(stats["freecell"], ModeStatistics())
    }

    func testResetClearsOnlyTheCombinationShown() {
        let model = makeModel()
        model.draw()
        model.newGame(drawThree)
        model.draw()
        model.newGame(drawThree)
        XCTAssertEqual(model.statistics["klondike.draw-1"].played, 1)
        XCTAssertEqual(model.statistics["klondike.draw-3"].played, 1)
        model.resetStatistics("klondike.draw-3")
        XCTAssertEqual(relaunch().statistics["klondike.draw-1"].played, 1)
        XCTAssertEqual(relaunch().statistics["klondike.draw-3"].played, 0)
    }

    func testFreeCellWinIsCountedApart() throws {
        func suit(_ suit: Suit, upTo rank: Int) -> [Card] { (1...rank).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        let game = FreeCell(
            cells: [[], [], [], []],
            foundations: [suit(.spades, upTo: 13), suit(.hearts, upTo: 13), suit(.diamonds, upTo: 13), suit(.clubs, upTo: 12)],
            tableau: [[Card(suit: .clubs, rank: 13, isFaceUp: true)]] + Array(repeating: [], count: 7)
        )
        defaults.set(try JSONEncoder().encode(game), forKey: "savedGame.freecell")
        defaults.set("freecell", forKey: "currentGame")
        let model = relaunch()
        XCTAssertTrue(model.move(from: .tableau(0), at: 0, to: .foundation(3)))
        XCTAssertEqual(model.statistics["freecell"].won, 1)
        XCTAssertEqual(model.statistics["klondike.draw-1"], ModeStatistics())
    }

    // MARK: - FreeCell board and VoiceOver

    func testFreeCellFitsAPhoneWithNarrowerCards() {
        let size = CGSize(width: 390, height: 700)
        let layout = BoardLayout(size: size, board: FreeCell(seed: 1).board)
        let klondike = BoardLayout(size: size, board: Klondike(seed: 1).board)
        XCTAssertLessThan(layout.cardSize.width, klondike.cardSize.width)
        XCTAssertGreaterThan(layout.cardSize.height / layout.cardSize.width, 1.4, "narrower, not just smaller")
        XCTAssertGreaterThan(layout.indexScale, 1)
        XCTAssertLessThanOrEqual(layout.slotCenter(.tableau(7)).x + layout.cardSize.width / 2, size.width)
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.cell(2))), .cell(2))
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.foundation(1))), .foundation(1))
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.tableau(7))), .tableau(7))
    }

    func testFreeCellLabels() {
        let ace = Card(suit: .hearts, rank: 1, isFaceUp: true)
        let six = Card(suit: .clubs, rank: 6, isFaceUp: true)
        let game = FreeCell(cells: [[ace], [], [], []], foundations: [[], [], [], []], tableau: [[six]] + Array(repeating: [], count: 7))
        XCTAssertEqual(Speech.label(for: ace, in: .cell(0), at: 0, of: game), "Free cell 1, Ace of hearts")
        XCTAssertEqual(Speech.emptyLabel(.cell(1), of: game), "Free cell 2, empty")
        XCTAssertEqual(Speech.label(for: six, in: .tableau(0), at: 0, of: game), "Column 1, 6 of clubs")
        XCTAssertEqual(Speech.moves(from: .tableau(0), at: 0, in: game).map(\.name), ["Move to Free cell 2"] + (2...8).map { "Move to Column \($0)" })
        XCTAssertEqual(Speech.moves(from: .cell(0), at: 0, in: game).first?.name, "Move to foundation")
        var after = game
        XCTAssertTrue(after.move(from: .tableau(0), at: 0, to: .cell(1)))
        XCTAssertEqual(Speech.moved(six, to: .cell(1), before: game, after: after, from: .tableau(0)), "6 of clubs moved to Free cell 2")
        XCTAssertEqual(Speech.hint(.move(Move(from: .cell(0), index: 0, to: .foundation(0))), in: game), "Hint: move Ace of hearts to foundation")
    }

    // MARK: - Yukon and Scorpion

    func testYukonAndScorpionFitAPhone() {
        let size = CGSize(width: 390, height: 700)
        for board in [Yukon(seed: 1).board, Scorpion(seed: 1).board] {
            let layout = BoardLayout(size: size, board: board)
            XCTAssertEqual(layout.pile(at: layout.slotCenter(.tableau(6))), .tableau(6))
            XCTAssertEqual(layout.pile(at: layout.slotCenter(.foundation(3))), board.spots.first { $0.pile == .foundation(3) }?.isDropTarget == true ? .foundation(3) : nil)
            XCTAssertLessThanOrEqual(layout.slotCenter(.tableau(6)).x + layout.cardSize.width / 2, size.width)
        }
    }

    func testScorpionReserveSpeech() {
        var game = Scorpion(seed: 1)
        XCTAssertEqual(Speech.stockLabel(game), "Deal the reserve")
        XCTAssertEqual(Speech.hint(.draw, in: game), "Hint: deal the reserve")
        XCTAssertTrue(game.draw())
        XCTAssertEqual(Speech.stockLabel(game), "Reserve empty")
        XCTAssertEqual(Speech.drew(game), "Reserve dealt")
    }

    // MARK: - Baker's Dozen and Eight Off

    func testBakersDozenAndEightOffFitAPhone() {
        let size = CGSize(width: 390, height: 700)
        for board in [BakersDozen(seed: 1).board, EightOff(seed: 1).board] {
            let layout = BoardLayout(size: size, board: board)
            for spot in board.spots where spot.pile.isTableau {
                let center = layout.slotCenter(spot.pile)
                XCTAssertGreaterThanOrEqual(center.x - layout.cardSize.width / 2, 0)
                XCTAssertLessThanOrEqual(center.x + layout.cardSize.width / 2, size.width)
            }
        }
        let layout = BoardLayout(size: size, board: BakersDozen(seed: 1).board)
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.tableau(12))), .tableau(12))
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.tableau(6))), .tableau(6))
    }
}
