import SolitaireCore
import SwiftUI

/// Confetti and the "You won!" banner. With Reduce Motion on, only the banner fades in.
struct WinOverlay: View {
    @ObservedObject var model: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confettiStart: Date?
    @State private var showsBanner = false

    var body: some View {
        ZStack {
            if let confettiStart {
                Confetti(start: confettiStart) { self.confettiStart = nil }
                    .ignoresSafeArea()
                // Tap anywhere to stop the confetti.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { self.confettiStart = nil }
                    .accessibilityHidden(true)
            }
            if showsBanner {
                banner
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onAppear {
            if !reduceMotion { confettiStart = Date() }
            withAnimation(reduceMotion ? .easeIn(duration: 0.4) : .spring(response: 0.45, dampingFraction: 0.7)) {
                showsBanner = true
            }
        }
    }

    private var banner: some View {
        VStack(spacing: 12) {
            Text("You won!").font(.largeTitle.bold())
            if let win = model.lastWin {
                (Text(verbatim: GameTime.format(win.time) + " · ") + Text("\(win.moves) moves"))
                    .font(.title3)
                    .monospacedDigit()
                if win.isBestTime {
                    Text("New best time!").font(.headline)
                }
                if win.isFewestMoves {
                    Text("Fewest moves yet!").font(.headline)
                }
            } else {
                Text("\(model.game.moveCount) moves").font(.title3)
            }
            Button("Play again") { withAnimation { model.newGame() } }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
                .accessibilityIdentifier("playAgain")
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("winBanner")
    }
}

/// "3:05", or "1:02:03" past an hour.
enum GameTime {
    static func format(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded(.down))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// One burst of falling paper, drawn with `Canvas` and stopped once the last piece has fallen.
private struct Confetti: View {
    let start: Date
    let onFinish: () -> Void

    /// The slowest, latest piece: 1.4 s delay plus 1 / 0.22 screens per second.
    private static let duration: TimeInterval = 6.5
    private static let pieces: [Piece] = {
        var rng = SplitMix64(seed: 2026)
        return (0..<140).map { _ in Piece(&rng) }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for piece in Self.pieces {
                    piece.draw(in: &context, size: size, time: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
            onFinish()
        }
    }

    private struct Piece {
        let x: Double
        let delay: Double
        /// Screen heights per second.
        let speed: Double
        let sway: Double
        let swayRate: Double
        let spin: Double
        let size: Double
        let color: Color
        let isRound: Bool

        private static let colors: [Color] = [
            Color(red: 0.96, green: 0.26, blue: 0.3), Color(red: 1, green: 0.8, blue: 0.2),
            Color(red: 0.3, green: 0.7, blue: 1), Color(red: 0.98, green: 0.98, blue: 0.96),
            Color(red: 0.6, green: 0.4, blue: 0.95), Color(red: 1, green: 0.55, blue: 0.2),
        ]

        init(_ rng: inout SplitMix64) {
            func unit() -> Double { Double(rng.next() % 10_000) / 10_000 }
            x = unit()
            delay = unit() * 1.4
            speed = 0.22 + unit() * 0.2
            sway = 8 + unit() * 22
            swayRate = 1.5 + unit() * 2.5
            spin = (unit() - 0.5) * 12
            size = 6 + unit() * 6
            color = Self.colors[Int(rng.next() % UInt64(Self.colors.count))]
            isRound = rng.next() % 4 == 0
        }

        func draw(in context: inout GraphicsContext, size canvas: CGSize, time: Double) {
            let t = time - delay
            guard t > 0 else { return }
            let y = -20 + t * speed * canvas.height
            guard y < canvas.height + 20 else { return }
            let center = CGPoint(x: x * canvas.width + sin(t * swayRate) * sway, y: y)
            var piece = context
            piece.translateBy(x: center.x, y: center.y)
            piece.rotate(by: .radians(t * spin))
            // Flutter: the paper turns, so its width shrinks and grows.
            let width = size * (isRound ? 1 : abs(cos(t * swayRate * 1.7)) * 0.8 + 0.2)
            let rect = CGRect(x: -width / 2, y: -size / 2, width: width, height: isRound ? size : size * 0.55)
            piece.fill(isRound ? Path(ellipseIn: rect) : Path(rect), with: .color(color))
        }
    }
}
