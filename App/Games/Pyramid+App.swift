import CoreGraphics
import SolitaireCore

extension Pyramid: PlayableGame {
    static var name: String { String(localized: "Pyramid") }

    static var ruleSettings: [RuleSetting] {
        [
            .picker(
                "Recycle the waste", \PyramidOptions.recycles, key: "recycle",
                choices: [(0, "Never", "never"), (1, "Once", "once"), (2, "Twice", "twice"), (-1, "Always", "always")]
            ),
        ]
    }

    /// Seven rows overlapping by half a card, then the stock, the waste and the foundation below. Cards leave
    /// their position empty, so positions draw no outline.
    var board: BoardSpec {
        BoardSpec(
            columns: Self.rowCount,
            heightInCards: 5.2,
            spots: [
                PileSpot(.stock, x: 0.5, y: 4, isDropTarget: false),
                PileSpot(.waste, x: 1.5, y: 4),
                PileSpot(.foundation(0), x: 5, y: 4),
            ] + (0..<Self.positionCount).map { position in
                let place = Self.coordinates(of: position)
                return PileSpot(.tableau(position), x: CGFloat(place.x), y: CGFloat(place.row) * 0.5, slot: nil)
            }
        )
    }

    /// "Row 3, card 2": the row counts from the top, the card from the left.
    func spokenName(of pile: Pile) -> String {
        guard case .tableau(let position) = pile else { return Speech.pileName(pile) }
        return String(localized: "Row \(Self.row(of: position) + 1), card \(Self.column(of: position) + 1)")
    }
}
