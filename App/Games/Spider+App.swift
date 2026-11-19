import CoreGraphics
import SolitaireCore

extension Spider: PlayableGame {
    static var name: String { String(localized: "Spider") }

    /// One, two or four suits: a variant, so each gets its own New-menu entry and statistics.
    static var ruleSettings: [RuleSetting] {
        [.picker("Suits", \SpiderOptions.suits, key: "suits", isVariant: true, choices: [(1, "1 suit", "1"), (2, "2 suits", "2"), (4, "4 suits", "4")])]
    }

    /// The stock at the top left and the eight foundations along the top right, above ten columns.
    var board: BoardSpec {
        var spots: [PileSpot] = [PileSpot(.stock, x: 0, y: 0, isDropTarget: false)]
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(2 + i), y: 0, slot: .text("K"), isDropTarget: false)) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down)) }
        return BoardSpec(columns: Self.tableauCount, heightInCards: 6, spots: spots)
    }
}
