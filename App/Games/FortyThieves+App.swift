import CoreGraphics
import SolitaireCore

extension FortyThieves: PlayableGame {
    static var name: String { String(localized: "Forty Thieves") }

    /// The stock and the waste at the top left, the eight foundations beside them, then ten columns.
    var board: BoardSpec {
        BoardSpec(
            columns: Self.tableauCount,
            heightInCards: 6,
            spots: [
                PileSpot(.stock, x: 0, y: 0, isDropTarget: false),
                PileSpot(.waste, x: 1, y: 0, isDropTarget: false),
            ] + (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(2 + $0), y: 0, slot: .text("A")) }
                + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down) }
        )
    }
}
