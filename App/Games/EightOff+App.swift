import CoreGraphics
import SolitaireCore

extension EightOff: PlayableGame {
    static var name: String { "Eight Off" }

    static var ruleSettings: [RuleSetting] {
        [.picker("Empty columns", \EightOffOptions.anyCardInEmptyColumn, key: "empty", choices: [(false, "Kings only", "kings"), (true, "Any card", "any")])]
    }

    /// Eight free cells in the top row, the four foundations centred below them, then eight columns.
    var board: BoardSpec {
        var spots: [PileSpot] = []
        for i in 0..<Self.cellCount { spots.append(PileSpot(.cell(i), x: CGFloat(i), y: 0)) }
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(2 + i), y: 1, slot: .text("A"))) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 2, fan: .down)) }
        return BoardSpec(columns: Self.tableauCount, heightInCards: 6.5, spots: spots)
    }
}
