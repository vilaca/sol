import CoreGraphics
import SolitaireCore

extension Yukon: PlayableGame {
    static var name: String { "Yukon" }

    /// The four foundations above seven columns.
    var board: BoardSpec {
        BoardSpec(columns: Self.tableauCount, spots: (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(3 + $0), y: 0, slot: .text("A")) }
            + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down, slot: .text("K")) })
    }
}
