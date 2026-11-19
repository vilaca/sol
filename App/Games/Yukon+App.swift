import CoreGraphics
import SolitaireCore

extension Yukon: PlayableGame {
    static var name: String { "Yukon" }

    /// The four foundations above seven columns.
    var board: BoardSpec {
        var spots: [PileSpot] = []
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(3 + i), y: 0, slot: .text("A"))) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down, slot: .text("K"))) }
        return BoardSpec(columns: Self.tableauCount, spots: spots)
    }
}
