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
        BoardSpec(columns: Self.tableauCount, spots: [
            PileSpot(.stock, x: 0, y: 0, slot: .symbol("arrow.counterclockwise"), isDropTarget: false),
            PileSpot(.waste, x: 1, y: 0, fan: .right(visible: drawCount), slot: nil, isDropTarget: false),
        ] + (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(3 + $0), y: 0, slot: .text("A")) }
            + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down, slot: .text("K")) })
    }
}
