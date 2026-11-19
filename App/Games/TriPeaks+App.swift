import CoreGraphics
import SolitaireCore

extension TriPeaks: PlayableGame {
    static var name: String { "TriPeaks" }

    static var ruleSettings: [RuleSetting] {
        [.toggle("Wrap King and Ace", \TriPeaksOptions.wrapsKingAndAce, key: "wrap")]
    }

    /// Three peaks whose rows overlap by half a card, then the stock and the waste. Cards leave their
    /// position empty, so positions draw no outline, and only the waste takes drops.
    var board: BoardSpec {
        BoardSpec(
            columns: 10,
            heightInCards: 4.2,
            spots: [
                PileSpot(.stock, x: 4, y: 3, isDropTarget: false),
                PileSpot(.waste, x: 5, y: 3),
            ] + (0..<Self.positionCount).map { position in
                let place = Self.coordinates(of: position)
                return PileSpot(.tableau(position), x: CGFloat(place.x), y: CGFloat(place.row) * 0.5, slot: nil, isDropTarget: false)
            }
        )
    }

    /// "Peak 2, row 3": the row counts from the top.
    func spokenName(of pile: Pile) -> String {
        guard case .tableau(let position) = pile else { return Speech.pileName(pile) }
        return String(localized: "Peak \(Self.peak(of: position) + 1), row \(Self.row(of: position) + 1)")
    }
}
