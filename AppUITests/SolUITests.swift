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
        app.buttons["new-klondike.draw-3"].tap()
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
        app.buttons["new-klondike.draw-3"].tap()
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
        app.buttons["new-klondike.draw-3"].tap()
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
        // A SwiftUI Link is a link on newer runtimes and a button on older ones; the list is lazy, so scroll to it.
        let link = app.descendants(matching: .any)["repositoryLink"]
        var swipes = 0
        while !link.exists && swipes < 3 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(link.exists)
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

    // MARK: - FreeCell

    /// Seed 42 deals FreeCell with the 10 of spades (card 9) on column 4 and the jack of hearts (card 23) on column 5.
    func testFreeCellDealMoveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-freecell"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cell-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(stock.exists, "FreeCell has no stock")
        XCTAssertTrue(app.buttons["Column 8, 9 of diamonds"].exists)
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["hint"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        app.buttons["card-9"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Column 5, 10 of spades"].waitForExistence(timeout: 2), "onto the jack of hearts")

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "FreeCell"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Yukon

    /// Seed 42 deals Yukon with the 10 of spades (card 9) alone in column 1 and the jack of hearts (card 23) on column 3.
    func testYukonDealMoveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-yukon"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["foundation-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(stock.exists, "Yukon has no stock")
        XCTAssertTrue(app.buttons["Column 1, 10 of spades"].exists)
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-9"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Column 3, 10 of spades"].waitForExistence(timeout: 2), "onto the jack of hearts")

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Yukon"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Scorpion

    /// Seed 42 deals Scorpion with the jack of hearts (card 23) on column 2 and the queen of hearts on column 3.
    func testScorpionDealMoveReserveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-scorpion"].tap()
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-23"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Column 3, Jack of hearts"].waitForExistence(timeout: 2), "onto the queen of hearts")
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")

        stock.tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.descendants(matching: .any)["stock-empty"].waitForExistence(timeout: 2), "the reserve is dealt once")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Scorpion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
    }

    // MARK: - Baker's Dozen

    /// Seed 42 deals Baker's Dozen with the ace of clubs (card 39) on top of column 1.
    func testBakersDozenDealMoveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-bakersdozen"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["foundation-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Column 1, Ace of clubs"].exists)
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-39"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Foundation, Ace of clubs"].waitForExistence(timeout: 2))

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Baker's Dozen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Eight Off

    /// Seed 42 deals Eight Off with the ace of spades (card 0) on top of column 1 and four cards in the free cells.
    func testEightOffDealMoveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-eightoff"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["foundation-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Free cell 1, Queen of diamonds"].exists)
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-0"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Foundation, Ace of spades"].waitForExistence(timeout: 2))

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Eight Off"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Golf

    /// Seed 42 deals Golf with the 2 of hearts on the waste and the 3 of spades (card 2) on top of column 2.
    func testGolfDealMoveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-golf"].tap()
        XCTAssertTrue(app.buttons["Waste, 2 of hearts"].waitForExistence(timeout: 5))
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-2"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Waste, 3 of spades"].waitForExistence(timeout: 2))

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Golf"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - TriPeaks

    /// Seed 42 deals TriPeaks with the 8 of spades (card 7) on the waste; the 7 of diamonds (card 32) is free.
    func testTriPeaksDealMoveAndUndo() {
        tapMenu("newGame")
        app.buttons["new-tripeaks"].tap()
        XCTAssertTrue(app.buttons["Peak 3, row 4, 7 of diamonds"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Peak 1, row 1"].exists, "covered cards are not read")
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-32"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Waste, 7 of diamonds"].waitForExistence(timeout: 2))

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "TriPeaks"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Pyramid

    /// Seed 42 deals Pyramid with the 10 of diamonds (card 35) and the 3 of hearts (card 15) free in the bottom row.
    func testPyramidDealPairAndUndo() {
        tapMenu("newGame")
        app.buttons["new-pyramid"].tap()
        XCTAssertTrue(app.buttons["Row 7, card 1, 10 of diamonds"].waitForExistence(timeout: 5))
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-35"].tap()
        XCTAssertEqual(moves.label, "Moves: 0", "the first card of a pair is only picked")
        app.buttons["card-15"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Foundation, 3 of hearts"].waitForExistence(timeout: 2))

        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
        XCTAssertTrue(app.buttons["Row 7, card 1, 10 of diamonds"].waitForExistence(timeout: 2))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Pyramid"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Spider

    /// Seed 42 deals one-suit Spider with the 9 of spades (card 112) on column 8 and the 10 of spades on column 1.
    func testSpiderDealMoveDealRowAndUndo() {
        tapMenu("newGame")
        XCTAssertTrue(app.buttons["new-spider.suits-1"].waitForExistence(timeout: 5))
        app.buttons["new-spider.suits-1"].tap()
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Column 8, 9 of spades, 4 hidden cards"].exists)
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-112"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Column 1, 9 of spades"].waitForExistence(timeout: 2), "onto the 10 of spades")
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")

        stock.tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Deal a row"].exists, "the stock still has four rows")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Spider"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
    }

    // MARK: - Forty Thieves

    /// Seed 42 deals Forty Thieves with the ace of diamonds (card 26) on top of column 4.
    func testFortyThievesDealMoveDrawAndUndo() {
        tapMenu("newGame")
        scrollMenuTo("new-fortythieves")
        app.buttons["new-fortythieves"].tap()
        XCTAssertTrue(app.buttons["Draw card, 64 left"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Column 4, Ace of diamonds"].exists)
        XCTAssertEqual(moves.label, "Moves: 0")

        app.buttons["card-26"].tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Foundation, Ace of diamonds"].waitForExistence(timeout: 2))
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")

        stock.tap()
        XCTAssertEqual(moves.label, "Moves: 1")
        XCTAssertTrue(app.buttons["Draw card, 63 left"].waitForExistence(timeout: 2))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Forty Thieves"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["undo"].tap()
        XCTAssertEqual(moves.label, "Moves: 0")
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

    /// The New menu lists every game; on a small screen its last entries sit below the fold until scrolled to.
    private func scrollMenuTo(_ identifier: String) {
        let item = app.buttons[identifier]
        var swipes = 0
        while !item.waitForExistence(timeout: 2) && swipes < 4 {
            // Drag an entry that is on screen; which ones are visible depends on the scroll position.
            let visible = ["new-klondike.draw-1", "new-klondike.draw-3", "new-freecell", "new-yukon"]
                .map { app.buttons[$0] }.first { $0.exists && $0.isHittable }
            (visible ?? app.windows.firstMatch).swipeUp()
            swipes += 1
        }
        XCTAssertTrue(item.exists)
    }

    private func openMenu(_ item: String) {
        tapMenu("more")
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.tap()
    }
}
