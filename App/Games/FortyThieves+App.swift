import CoreGraphics
import SolitaireCore

extension FortyThieves: PlayableGame {
    static var name: String { String(localized: "Forty Thieves") }

    /// The stock and the waste at the top left, the eight foundations beside them, then ten columns.
    var board: BoardSpec {
        var spots: [PileSpot] = [
            PileSpot(.stock, x: 0, y: 0, isDropTarget: false),
            PileSpot(.waste, x: 1, y: 0, isDropTarget: false),
        ]
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(2 + i), y: 0, slot: .text("A"))) }
        for i in 0..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down)) }
        return BoardSpec(
            columns: Self.tableauCount,
            heightInCards: 6,
            spots: spots
        )
    }
}
