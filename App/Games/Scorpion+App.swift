import CoreGraphics
import SolitaireCore

extension Scorpion: PlayableGame {
    static var name: String { String(localized: "Scorpion") }

    /// The reserve (the stock) and the four foundations above seven columns.
    var board: BoardSpec {
        BoardSpec(columns: Self.tableauCount, spots: [
            PileSpot(.stock, x: 0, y: 0, slot: .blank, isDropTarget: false),
        ] + (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(3 + $0), y: 0, slot: .text("K"), isDropTarget: false) }
            + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down, slot: .text("K")) })
    }
}
