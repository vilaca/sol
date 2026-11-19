import CoreGraphics
import SolitaireCore

extension FreeCell: PlayableGame {
    static var name: String { "FreeCell" }

    // No rule options yet. One would be a stored property in `FreeCellOptions` plus a line here, e.g.
    // `[.toggle("Empty columns take kings only", \FreeCellOptions.kingsOnly, key: "kings")]`.

    /// Four free cells and four foundations above eight columns.
    var board: BoardSpec {
        var spots: [PileSpot] = []
        for i in 0..<Self.cellCount { spots.append(PileSpot(.cell(i), x: CGFloat(i), y: 0)) }
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(4 + i), y: 0, slot: .text("A"))) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down)) }
        return BoardSpec(columns: Self.tableauCount, spots: spots)
    }
}
