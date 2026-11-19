import CoreGraphics
import SolitaireCore

extension Golf: PlayableGame {
    static var name: String { String(localized: "Golf") }

    static var ruleSettings: [RuleSetting] {
        [.toggle("Wrap King and Ace", \GolfOptions.wrapsKingAndAce, key: "wrap")]
    }

    /// Seven columns with the stock and the waste centred below them. Only the waste takes drops.
    var board: BoardSpec {
        BoardSpec(
            columns: Self.tableauCount,
            heightInCards: 4.2,
            spots: [
                PileSpot(.stock, x: 2.5, y: 2.6, isDropTarget: false),
                PileSpot(.waste, x: 3.5, y: 2.6),
            ] + (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 0, fan: .down, slot: nil, isDropTarget: false) }
        )
    }
}
