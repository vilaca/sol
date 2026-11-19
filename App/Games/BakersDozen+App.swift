import CoreGraphics
import SolitaireCore

extension BakersDozen: PlayableGame {
    static var name: String { "Baker's Dozen" }

    /// The four foundations above thirteen columns, laid out as two rows (7 + 6) so the cards stay big enough.
    /// Empty columns draw nothing: they stay empty.
    var board: BoardSpec {
        var spots: [PileSpot] = []
        for i in 0..<Self.foundationCount { spots.append(PileSpot(.foundation(i), x: CGFloat(1.5 + Double(i)), y: 0, slot: .text("A"))) }
        for i in 0..<7 { spots.append(PileSpot(.tableau(i), x: CGFloat(i), y: 1, fan: .down, slot: nil)) }
        for i in 7..<Self.tableauCount { spots.append(PileSpot(.tableau(i), x: CGFloat(i - 7) + 0.5, y: 2.6, fan: .down, slot: nil)) }
        return BoardSpec(columns: 7, heightInCards: 6.5, spots: spots)
    }
}
