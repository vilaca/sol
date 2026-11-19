import XCTest

/// Runs against a fixed deal (`-seed 42`) with no saved state (`-reset`), so results are repeatable.
final class SolUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seed", "42", "-reset"]
        app.launch()
    }

    private var moves: XCUIElement { app.staticTexts["moves"] }
    private var stock: XCUIElement { app.buttons["stock"].firstMatch }

    func testBoardAppearsWithFreshGame() {
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        XCTAssertEqual(moves.label, "Moves: 0")
        XCTAssertFalse(app.buttons["undo"].isEnabled)
        XCTAssertEqual(app.staticTexts["timer"].label, "Time 0:00")
    }

    func testTimerRunsAfterFirstMove() {
        stock.tap()
        let timer = app.staticTexts["timer"]
        let running = NSPredicate(format: "label != 'Time 0:00'")
        expectation(for: running, evaluatedWith: timer)
        waitForExpectations(timeout: 4)
    }

    func testDrawingAndUndo() {
        stock.tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
    }

    func testNewGameMidGameAsksBeforeCountingALoss() {
        stock.tap()
        tapMenu("newGame")
        app.buttons["New Game – Draw 3"].tap()
        let abandon = app.buttons["abandon"].firstMatch
        XCTAssertTrue(abandon.waitForExistence(timeout: 2))
        abandon.tap()
        XCTAssertEqual(moves.label, "Moves: 0")

        openMenu("statistics")
        app.buttons["Draw 1"].tap()
        XCTAssertTrue(app.staticTexts["Played, 1"].waitForExistence(timeout: 2), "the abandoned game is counted")
        XCTAssertTrue(app.staticTexts["Won, 0"].exists)
        app.buttons["done"].tap()
    }

    func testNewGameBeforeAnyMoveDealsAtOnce() {
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        XCTAssertEqual(moves.label, "Moves: 0")
        tapMenu("newGame")
        app.buttons["New Game – Draw 3"].tap()
        XCTAssertFalse(app.buttons["abandon"].waitForExistence(timeout: 1))
        XCTAssertEqual(moves.label, "Moves: 0")
    }

    func testSettingsHideTheTimer() {
        XCTAssertTrue(app.staticTexts["timer"].waitForExistence(timeout: 5))
        openMenu("settings")
        let toggle = app.switches["timerToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.switches.firstMatch.tap()
        app.buttons["done"].tap()
        XCTAssertFalse(app.staticTexts["timer"].waitForExistence(timeout: 1))
    }

    /// Seed 42 deals the jack of spades (card 10) in column 2, the 10 of diamonds (card 35) on column 7,
    /// the 6 of spades (card 5) on column 5 and the 8 of hearts (card 20) on column 6.
    func testDraggingCards() {
        let tenOfDiamonds = app.buttons["card-35"]
        XCTAssertTrue(tenOfDiamonds.waitForExistence(timeout: 5))
        let start = tenOfDiamonds.frame
        app.buttons["card-5"].press(forDuration: 0.1, thenDragTo: app.buttons["card-20"])
        XCTAssertEqual(moves.label, "Moves: 0", "a 6 can't go on an 8")

        tenOfDiamonds.press(forDuration: 0.1, thenDragTo: app.buttons["card-10"])
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertNotEqual(tenOfDiamonds.frame, start)
        XCTAssertEqual(tenOfDiamonds.frame.minX, app.buttons["card-10"].frame.minX, accuracy: 2)
    }

    func testHintLeavesTheGameAlone() {
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        app.buttons["hint"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        XCTAssertFalse(app.alerts["No moves left"].exists)
    }

    /// Seed 1510 dealt for draw 3 has no useful move from the start.
    func testWarnsWhenNoMovesAreLeft() {
        app.terminate()
        app.launchArguments = ["-seed", "1510", "-reset"]
        app.launch()
        tapMenu("newGame")
        app.buttons["New Game – Draw 3"].tap()
        let alert = app.alerts["No moves left"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Keep Playing"].tap()

        stock.tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1), "asked once per dead end, not on every draw")
        app.buttons["hint"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 2), "the hint button says so again")
        alert.buttons["New Game"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
    }

    func testAboutSaysItIsFreeAndLinksToTheCode() {
        openMenu("about")
        XCTAssertTrue(app.staticTexts["100% free: no pay to play, no pay to win"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["No ads"].exists)
        XCTAssertTrue(app.links["repositoryLink"].exists)
        app.buttons["done"].tap()
        XCTAssertTrue(stock.waitForExistence(timeout: 2))
    }

    func testGameSurvivesRelaunch() {
        stock.tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertEqual(moves.label, "Moves: 1")
    }

    // MARK: - VoiceOver

    func testVoiceOverLabelsSayWhereCardsAre() {
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        // XCUITest also lists elements VoiceOver skips (cards under the top one), so match by label.
        XCTAssertTrue(app.buttons["Draw card, 24 left"].exists)
        let columnOne = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Column 1, '")).firstMatch
        XCTAssertTrue(columnOne.exists)
        let columnSeven = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Column 7, ' AND label ENDSWITH ', 6 hidden cards'")).firstMatch
        XCTAssertTrue(columnSeven.exists, "the top card of column 7 says how many cards are hidden under it")

        stock.tap()
        XCTAssertTrue(app.buttons["Draw card, 23 left"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Waste, '")).firstMatch.exists)
    }

    func testAccessibilityAudit() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Accessibility audits need iOS 17") }
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        // Contrast is left out: the felt and the white outlines of empty piles are deliberately faint.
        // Dynamic Type is left out: card faces scale with the card, not with the text size.
        try app.performAccessibilityAudit(for: [.elementDetection, .hitRegion, .sufficientElementDescription, .trait])
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Taps a toolbar menu at its centre, like a finger. A plain `tap()` on a SwiftUI `Menu` fails on the
    /// iOS 26 simulator ("failed to scroll to visible … kAXErrorCannotComplete"), though the menu works.
    private func tapMenu(_ identifier: String) {
        let menu = app.buttons[identifier]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func openMenu(_ item: String) {
        tapMenu("more")
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.tap()
    }
}
