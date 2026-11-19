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
        BoardSpec(
            columns: Self.tableauCount,
            heightInCards: 6,
            spots: [PileSpot(.stock, x: 0, y: 0, isDropTarget: false)]
                + (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(2 + $0), y: 0, slot: .text("K"), isDropTarget: false) }
                + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down) }
        )
    }
}
