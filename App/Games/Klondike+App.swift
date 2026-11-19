import CoreGraphics
import SolitaireCore

extension Klondike: PlayableGame {
    static var name: String { "Klondike" }

    static var ruleSettings: [RuleSetting] {
        [
            .picker("Deal", \KlondikeOptions.drawCount, key: "draw", isVariant: true, choices: [
                (1, "Draw 1", "1"),
                (3, "Draw 3", "3"),
            ]),
        ]
    }

    /// Stock, waste and the four foundations above seven columns.
    var board: BoardSpec {
        var spots: [PileSpot] = [
            PileSpot(.stock, x: 0, y: 0, slot: .symbol("arrow.counterclockwise"), isDropTarget: false),
            PileSpot(.waste, x: 1, y: 0, fan: .right(visible: drawCount), slot: nil, isDropTarget: false),
        ]
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(3 + i), y: 0, slot: .text("A"))) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down, slot: .text("K"))) }
        return BoardSpec(columns: Self.tableauCount, spots: spots)
    }
}
