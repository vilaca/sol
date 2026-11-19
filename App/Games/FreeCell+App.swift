import CoreGraphics
import SolitaireCore

extension FreeCell: PlayableGame {
    static var name: String { "FreeCell" }

    // No rule options yet. One would be a stored property in `FreeCellOptions` plus a line here, e.g.
    // `[.toggle("Empty columns take kings only", \FreeCellOptions.kingsOnly, key: "kings")]`.

    /// Four free cells and four foundations above eight columns.
    var board: BoardSpec {
        BoardSpec(columns: Self.tableauCount, spots: (0..<Self.cellCount).map { PileSpot(.cell($0), x: CGFloat($0), y: 0) }
            + (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(4 + $0), y: 0, slot: .text("A")) }
            + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down) })
    }
}
