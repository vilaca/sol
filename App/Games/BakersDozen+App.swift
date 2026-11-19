import CoreGraphics
import SolitaireCore

extension BakersDozen: PlayableGame {
    static var name: String { "Baker's Dozen" }

    /// The four foundations above thirteen columns, laid out as two rows (7 + 6) so the cards stay big enough.
    /// Empty columns draw nothing: they stay empty.
    var board: BoardSpec {
        BoardSpec(
            columns: 7,
            heightInCards: 6.5,
            spots: (0..<Self.foundationCount).map { PileSpot(.foundation($0), x: CGFloat(1.5 + Double($0)), y: 0, slot: .text("A")) }
                + (0..<7).map { PileSpot(.tableau($0), x: CGFloat($0), y: 1, fan: .down, slot: nil) }
                + (7..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0 - 7) + 0.5, y: 2.6, fan: .down, slot: nil) }
        )
    }
}
