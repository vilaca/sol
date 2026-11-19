import CoreGraphics
import SolitaireCore

extension Scorpion: PlayableGame {
    static var name: String { String(localized: "Scorpion") }

    /// The reserve (the stock) and the four foundations above seven columns.
    var board: BoardSpec {
        var spots: [PileSpot] = [PileSpot(.stock, x: 0, y: 0, slot: .blank, isDropTarget: false)]
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(3 + i), y: 0, slot: .text("K"), isDropTarget: false)) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down, slot: .text("K"))) }
        return BoardSpec(columns: Self.tableauCount, spots: spots)
    }
}
