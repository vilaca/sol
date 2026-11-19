import SolitaireCore
import XCTest
@testable import Sol
@testable import SolitaireCore

/// A clock the tests move by hand.
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

@MainActor
final class GameModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "GameModelTests"
    private let clock = TestClock()

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeModel(seed: UInt64? = 42) -> GameModel {
        GameModel(launch: LaunchOptions(seed: seed), defaults: defaults, now: { [clock] in clock.now })
    }

    /// Saves a game one move from the win (the king of clubs, alone in column 1) and loads it.
    private func makeNearlyWonModel(drawCount: Int = 1) throws -> GameModel {
        func suit(_ suit: Suit, upTo rank: Int) -> [Card] { (1...rank).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        let game = Klondike(
            stock: [],
            waste: [],
            foundations: [suit(.spades, upTo: 13), suit(.hearts, upTo: 13), suit(.diamonds, upTo: 13), suit(.clubs, upTo: 12)],
            tableau: [[Card(suit: .clubs, rank: 13, isFaceUp: true)]] + Array(repeating: [], count: 6),
            drawCount: drawCount
        )
        defaults.set(try JSONEncoder().encode(game), forKey: "savedGame")
        return makeModel(seed: nil)
    }

    // MARK: - Game state

    func testSeedGivesKnownDeal() {
        XCTAssertEqual(makeModel().game, Klondike(seed: 42))
    }

    func testUndoRestoresPreviousState() {
        let model = makeModel()
        let start = model.game
        XCTAssertFalse(model.canUndo)
        model.draw()
        XCTAssertNotEqual(model.game, start)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.game, start)
        XCTAssertFalse(model.canUndo)
    }

    func testGameIsRestoredOnNextLaunch() {
        let first = makeModel(seed: 7)
        first.draw()
        let second = GameModel(defaults: defaults)
        XCTAssertEqual(second.game, first.game)
    }

    func testResetIgnoresSavedGame() {
        let first = makeModel(seed: 7)
        first.draw()
        let second = GameModel(launch: LaunchOptions(reset: true), defaults: defaults)
        XCTAssertEqual(second.game.moveCount, 0)
    }

    func testNewGameRemembersDrawCount() {
        let model = makeModel(seed: 1)
        model.newGame(drawCount: 3)
        XCTAssertEqual(model.game.drawCount, 3)
        XCTAssertEqual(GameModel(launch: LaunchOptions(reset: false), defaults: defaults).game.drawCount, 3)
    }

    func testPreferredDrawCountAppliesToNextGame() {
        let model = makeModel()
        model.preferredDrawCount = 3
        XCTAssertEqual(model.game.drawCount, 1)
        model.newGame()
        XCTAssertEqual(model.game.drawCount, 3)
    }

    func testDraggedCardLandsOnPileUnderItsCentre() {
        let layout = BoardLayout(size: CGSize(width: 390, height: 700))
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.foundation(2))), .foundation(2))
        XCTAssertEqual(layout.pile(at: layout.slotCenter(.tableau(6))), .tableau(6))
        XCTAssertNil(layout.pile(at: layout.slotCenter(.waste)))
    }

    func testBoardFitsLandscapeIPad() {
        let layout = BoardLayout(size: CGSize(width: 1180, height: 760))
        XCTAssertLessThanOrEqual(layout.cardSize.height * 5.5, 760)
        XCTAssertGreaterThan(layout.inset, layout.spacing)
    }

    // MARK: - Timer

    func testTimerStartsOnFirstMove() {
        let model = makeModel()
        clock.advance(30)
        XCTAssertEqual(model.elapsed(), 0)
        model.draw()
        clock.advance(12)
        XCTAssertEqual(model.elapsed(), 12)
    }

    func testTimerPausesAndResumes() {
        let model = makeModel()
        model.draw()
        clock.advance(10)
        model.setPaused(true)
        clock.advance(100)
        XCTAssertEqual(model.elapsed(), 10)
        model.setPaused(false)
        clock.advance(5)
        XCTAssertEqual(model.elapsed(), 15)
    }

    func testTimerIsSavedWithTheGame() {
        let first = makeModel(seed: 7)
        first.draw()
        clock.advance(20)
        first.setPaused(true)
        let second = GameModel(defaults: defaults, now: { [clock] in clock.now })
        XCTAssertEqual(second.elapsed(), 20)
        clock.advance(3)
        XCTAssertEqual(second.elapsed(), 23, "a restored started game keeps counting")
    }

    func testUndoDoesNotRewindTime() {
        let model = makeModel()
        model.draw()
        clock.advance(8)
        model.undo()
        XCTAssertEqual(model.game.moveCount, 0)
        XCTAssertEqual(model.elapsed(), 8)
    }

    // MARK: - Statistics

    func testWinRecordsStatisticsAndStopsTheClock() throws {
        let model = try makeNearlyWonModel()
        XCTAssertTrue(model.move(from: .tableau(0), at: 0, to: .foundation(3)))
        XCTAssertTrue(model.game.isWon)
        let stats = model.statistics.drawOne
        XCTAssertEqual(stats.played, 1)
        XCTAssertEqual(stats.won, 1)
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.fewestMoves, 1)
        XCTAssertEqual(model.lastWin?.moves, 1)
        XCTAssertFalse(model.canUndo, "a won game can't be undone and counted twice")
        clock.advance(60)
        XCTAssertEqual(model.elapsed(), 0)
    }

    func testAbandoningStartedGameIsALoss() {
        let model = makeModel()
        XCTAssertFalse(model.isInProgress)
        model.newGame()
        XCTAssertEqual(model.statistics.drawOne.played, 0, "a deal with no moves isn't counted")
        model.draw()
        XCTAssertTrue(model.isInProgress)
        model.newGame(drawCount: 3)
        XCTAssertEqual(model.statistics.drawOne.played, 1)
        XCTAssertEqual(model.statistics.drawOne.won, 0)
        XCTAssertEqual(model.statistics.drawThree.played, 0)
    }

    func testStatisticsSurviveRelaunchAndReset() {
        let model = makeModel()
        model.draw()
        model.newGame()
        XCTAssertEqual(GameModel(defaults: defaults).statistics.drawOne.played, 1)
        model.resetStatistics()
        XCTAssertEqual(GameModel(defaults: defaults).statistics, Statistics())
    }
}

final class StatisticsTests: XCTestCase {
    func testStreaksAndBests() {
        var stats = Statistics()
        let first = stats.recordWin(drawCount: 1, time: 200, moves: 120)
        XCTAssertFalse(first.isBestTime, "a first win sets the record without announcing it")
        let second = stats.recordWin(drawCount: 1, time: 150, moves: 130)
        XCTAssertTrue(second.isBestTime)
        XCTAssertFalse(second.isFewestMoves)
        stats.recordLoss(drawCount: 1)
        _ = stats.recordWin(drawCount: 1, time: 300, moves: 100)

        let mode = stats.drawOne
        XCTAssertEqual(mode.played, 4)
        XCTAssertEqual(mode.won, 3)
        XCTAssertEqual(mode.currentStreak, 1)
        XCTAssertEqual(mode.bestStreak, 2)
        XCTAssertEqual(mode.bestTime, 150)
        XCTAssertEqual(mode.fewestMoves, 100)
        XCTAssertEqual(mode.winRate, 0.75)
        XCTAssertEqual(stats.drawThree, ModeStatistics(), "draw 3 is kept apart")
    }

    func testNoGamesHasNoWinRate() {
        XCTAssertNil(ModeStatistics().winRate)
    }

    func testTimeFormat() {
        XCTAssertEqual(GameTime.format(0), "0:00")
        XCTAssertEqual(GameTime.format(65.9), "1:05")
        XCTAssertEqual(GameTime.format(3723), "1:02:03")
    }
}
