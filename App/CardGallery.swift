#if DEBUG
import SolitaireCore
import SwiftUI

/// Every card face plus the back, for checking card designs. Launch with `-cardGallery` (Debug builds only).
struct CardGallery: View {
    var body: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - 8 * 4) / 7
            let size = CGSize(width: width, height: width * 1.4)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 4), count: 7), spacing: 6) {
                    ForEach(Card.fullDeck.map { Card(suit: $0.suit, rank: $0.rank, isFaceUp: true) }) { card in
                        CardView(card: card, size: size)
                    }
                    CardView(card: Card(suit: .spades, rank: 1), size: size)
                }
                .padding(4)
            }
        }
        .background(Color(red: 0.05, green: 0.35, blue: 0.2).ignoresSafeArea())
    }
}
#endif
