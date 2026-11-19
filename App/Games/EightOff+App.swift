import CoreGraphics
import SolitaireCore

extension EightOff: PlayableGame {
    static var name: String { "Eight Off" }

    static var ruleSettings: [RuleSetting] {
        [.picker("Empty columns", \EightOffOptions.anyCardInEmptyColumn, key: "empty", choices: [(false, "Kings only", "kings"), (true, "Any card", "any")])]
    }

    /// Eight free cells in the top row, the four foundations centred below them, then eight columns.
    var board: BoardSpec {
        BoardSpec(
            columns: Self.tableauCount,
            heightInCards: 6.5,
            spots: (0..<Self.cellCount).map { PileSpot(.cell($0), x: CGFloat($0), y: 0) }
                + (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(2 + $0), y: 1, slot: .text("A")) }
                + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 2, fan: .down) }
        )
    }
}
