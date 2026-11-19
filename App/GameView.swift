import SolitaireCore
import SwiftUI

private struct DragState {
    let pile: Pile
    let index: Int
    var translation: CGSize
}

/// The cards that shake after a tap that has nowhere to go: the tapped card and those on top of it.
private struct ShakeTarget: Equatable {
    let pile: Pile
    let index: Int
}

struct GameView: View {
    @ObservedObject var model: GameModel
    /// Resets by itself when the gesture ends or is cancelled (a call, Control Center), springing the cards back.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.85)))
    private var drag: DragState?
    @State private var shakeTarget: ShakeTarget?
    @State private var shakeProgress: CGFloat = 0
    @State private var sheet: MenuSheet?
    /// Deal mode of a New Game waiting for "Abandon this game?" to be confirmed.
    @State private var pendingDrawCount: Int?
    /// The hint being shown; cleared after a moment or by the next move.
    @State private var hint: Hint?
    @State private var showsNoMoves = false
    /// "No moves left" was shown for the current dead end; asked again only after a way out appeared.
    @State private var warnedNoMoves = false
    @AppStorage(PreferenceKey.showTimer) private var showTimer = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let board = "board"

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                board(BoardLayout(size: geometry.size))
            }
            toolbar
        }
        .background(felt.ignoresSafeArea())
        .overlay {
            if model.game.isWon { WinOverlay(model: model) }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .statistics: StatisticsView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        // `onChange` closures see the view as it was before the change, so pass the new value in.
        .onAppear { updatePause(phase: scenePhase, sheet: sheet) }
        .onChange(of: scenePhase) { phase in updatePause(phase: phase, sheet: sheet) }
        .onChange(of: sheet) { sheet in updatePause(phase: scenePhase, sheet: sheet) }
        .onChange(of: model.game.isWon) { won in
            guard won else { return }
            Haptics.won()
            Speech.announce(Speech.won)
        }
        .onChange(of: model.game) { game in
            hint = nil
            warnIfStuck(game)
        }
        .onAppear { warnIfStuck(model.game) }
        .alert(Text("No moves left"), isPresented: $showsNoMoves) {
            Button("New Game", role: .destructive) { withAnimation { model.newGame() } }
            if model.canUndo {
                Button("Undo") { withAnimation(.easeInOut(duration: 0.2)) { model.undo() } }
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Undo, or deal a new game. A new game counts as a loss.")
        }
    }

    /// The clock runs only while the game is on screen.
    private func updatePause(phase: ScenePhase, sheet: MenuSheet?) {
        model.setPaused(phase != .active || sheet != nil)
    }

    // MARK: - Board

    private func board(_ layout: BoardLayout) -> some View {
        ZStack(alignment: .topLeading) {
            slots(layout)
            ForEach(layout.place(model.game, raised: model.movedCards)) { placed in
                cardView(placed, layout)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.board)
        // VoiceOver reads the top row, then each column top to bottom (see `readingOrder`).
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func slots(_ layout: BoardLayout) -> some View {
        let game = model.game
        SlotView(size: layout.cardSize, symbol: "arrow.counterclockwise")
            .modifier(HintGlow(isOn: hint == .draw && game.stock.isEmpty, size: layout.cardSize))
            .onTapGesture { draw() }
            .accessibilityElement()
            .accessibilityLabel(Speech.stockLabel(game))
            .accessibilityIdentifier("stock-empty")
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(!game.stock.isEmpty)
            .accessibilitySortPriority(Self.readingOrder(.stock, 0))
            .position(layout.slotCenter(.stock))
        ForEach(0..<Klondike.foundationCount, id: \.self) { f in
            SlotView(size: layout.cardSize, text: "A")
                .modifier(HintGlow(isOn: game.foundations[f].isEmpty && hintDestination == .foundation(f), size: layout.cardSize))
                .accessibilityElement()
                .accessibilityLabel(Text("Empty foundation"))
                .accessibilityIdentifier("foundation-\(f)")
                .accessibilityHidden(!game.foundations[f].isEmpty)
                .accessibilitySortPriority(Self.readingOrder(.foundation(f), 0))
                .position(layout.slotCenter(.foundation(f)))
        }
        ForEach(0..<Klondike.tableauCount, id: \.self) { t in
            SlotView(size: layout.cardSize, text: "K")
                .modifier(HintGlow(isOn: game.tableau[t].isEmpty && hintDestination == .tableau(t), size: layout.cardSize))
                .accessibilityElement()
                .accessibilityLabel(Speech.emptyColumnLabel(t))
                .accessibilityIdentifier("tableau-\(t)")
                .accessibilityHidden(!game.tableau[t].isEmpty)
                .accessibilitySortPriority(Self.readingOrder(.tableau(t), 0))
                .position(layout.slotCenter(.tableau(t)))
        }
    }

    private func cardView(_ placed: PlacedCard, _ layout: BoardLayout) -> some View {
        let game = model.game
        let isDragged = drag.map { $0.pile == placed.pile && placed.index >= $0.index } ?? false
        let isShaking = shakeTarget.map { $0.pile == placed.pile && placed.index >= $0.index } ?? false
        let isTop = placed.index == game.cards(in: placed.pile).count - 1
        let isAccessible = if case .tableau = placed.pile { placed.card.isFaceUp } else { isTop }
        let label = isAccessible ? Speech.label(for: placed.card, in: placed.pile, at: placed.index, of: game) : nil
        // Not rebuilt on every drag frame: VoiceOver users don't drag.
        let moves = drag == nil && isAccessible && canDrag(placed) ? Speech.moves(from: placed.pile, at: placed.index, in: game) : []
        return CardView(card: placed.card, size: layout.cardSize, accessibilityText: label, isHinted: isHinted(placed, isTop: isTop))
            .modifier(ShakeEffect(progress: isShaking ? shakeProgress : 0))
            .offset(isDragged ? drag?.translation ?? .zero : .zero)
            .gesture(dragGesture(placed, layout), including: canDrag(placed) ? .all : .subviews)
            .onTapGesture { tap(placed) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap(placed) }
            .modifier(AccessibleMoves(moves: moves) { move in
                _ = perform(placed, to: move.destination, animation: .easeInOut(duration: 0.2))
            })
            .accessibilityIdentifier(placed.pile == .stock ? "stock" : placed.card.isFaceUp ? "card-\(placed.card.id)" : "card-hidden")
            .accessibilityHidden(!isAccessible)
            .accessibilitySortPriority(Self.readingOrder(placed.pile, placed.index))
            .position(placed.center)
            .zIndex(isDragged ? 1000 + placed.zIndex : placed.zIndex)
    }

    /// The cards the hint moves, the top card they go onto, or the stock to draw from.
    private func isHinted(_ placed: PlacedCard, isTop: Bool) -> Bool {
        switch hint {
        case .move(let move): (placed.pile == move.from && placed.index >= move.index) || (placed.pile == move.to && isTop)
        case .draw: placed.pile == .stock && isTop
        case nil: false
        }
    }

    private var hintDestination: Pile? {
        if case .move(let move) = hint { move.to } else { nil }
    }

    private func showHint() {
        guard !model.isAutoCompleting, !model.game.isWon else { return }
        guard let next = model.game.hint else {
            showsNoMoves = true
            Speech.announce(Speech.noMovesLeft)
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { hint = next }
        Speech.announce(Speech.hint(next, in: model.game))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if hint == next { withAnimation(.easeInOut(duration: 0.4)) { hint = nil } }
        }
    }

    /// Says "No moves left" once per dead end, so drawing through a stuck stock doesn't ask again on every card.
    private func warnIfStuck(_ game: Klondike) {
        guard !game.isWon, !model.isAutoCompleting else { return }
        if game.hint != nil {
            warnedNoMoves = false
        } else if !warnedNoMoves {
            warnedNoMoves = true
            showsNoMoves = true
            Speech.announce(Speech.noMovesLeft)
        }
    }

    /// Higher is read first: stock, waste, foundations, then column 1 top to bottom, column 2, …
    private static func readingOrder(_ pile: Pile, _ index: Int) -> Double {
        switch pile {
        case .stock: 1000
        case .waste: 999
        case .foundation(let f): Double(990 - f)
        case .tableau(let t): Double(900 - t * 40 - index)
        }
    }

    private func canDrag(_ placed: PlacedCard) -> Bool {
        guard placed.card.isFaceUp, !model.isAutoCompleting else { return false }
        if case .tableau = placed.pile { return true }
        return placed.index == model.game.cards(in: placed.pile).count - 1
    }

    /// A tap sends the card to the best pile (a foundation first). With nowhere to go, it shakes.
    private func tap(_ placed: PlacedCard) {
        guard !model.isAutoCompleting, !model.game.isWon else { return }
        if placed.pile == .stock {
            draw()
        } else if canDrag(placed) {
            if let destination = model.game.bestDestination(from: placed.pile, at: placed.index) {
                _ = perform(placed, to: destination, animation: .easeInOut(duration: 0.2))
            } else {
                rejected()
                shake(placed)
            }
        }
    }

    /// Moves the card (and those on top of it), with haptic and VoiceOver feedback.
    /// `placed` may be stale (the game changed during a drag), so the index is checked first.
    private func perform(_ placed: PlacedCard, to destination: Pile, animation: Animation) -> Bool {
        let before = model.game
        let source = before.cards(in: placed.pile)
        guard source.indices.contains(placed.index), source[placed.index].id == placed.card.id else { return false }
        let moved = withAnimation(animation) {
            model.move(from: placed.pile, at: placed.index, to: destination)
        }
        if moved {
            Haptics.moved(toFoundation: destination.isFoundation)
            // The winning move is announced as "You won!" (see onChange), not cut off by this one.
            if !model.game.isWon {
                Speech.announce(Speech.moved(source[placed.index], to: destination, before: before, after: model.game, from: placed.pile))
            }
        }
        return moved
    }

    private func rejected() {
        Haptics.rejected()
        Speech.announce(Speech.notAllowed)
    }

    private func shake(_ placed: PlacedCard) {
        guard shakeTarget == nil else { return }
        shakeTarget = ShakeTarget(pile: placed.pile, index: placed.index)
        withAnimation(.linear(duration: 0.4)) { shakeProgress = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                shakeProgress = 0
                shakeTarget = nil
            }
        }
    }

    /// Drawing slides the card to the waste. Turning the waste back over happens at once: animated,
    /// the cards would visibly fly back face up while they flip.
    private func draw() {
        guard !model.isAutoCompleting else { return }
        let drew = model.game.stock.isEmpty ? model.draw() : withAnimation(.easeInOut(duration: 0.2)) { model.draw() }
        if drew { Speech.announce(Speech.drew(model.game)) }
    }

    private func dragGesture(_ placed: PlacedCard, _ layout: BoardLayout) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.board))
            .updating($drag) { value, state, _ in
                if state == nil { Haptics.pickUp() }
                state = DragState(pile: placed.pile, index: placed.index, translation: value.translation)
            }
            .onEnded { value in
                let dropped = CGPoint(
                    x: placed.center.x + value.translation.width,
                    y: placed.center.y + value.translation.height
                )
                let target = layout.pile(at: dropped)
                // Dropped back where it came from: no move, no complaint. The waste has no drop target,
                // so "where it came from" also means still over the card's own spot.
                let stayed = abs(value.translation.width) < layout.cardSize.width / 2
                    && abs(value.translation.height) < layout.cardSize.height / 2
                guard target != placed.pile, !stayed else { return }
                if let target, perform(placed, to: target, animation: .spring(response: 0.3, dampingFraction: 0.85)) {
                    return
                }
                rejected()
            }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: horizontalSizeClass == .regular ? 16 : 0) {
            Menu {
                Button("New Game – Draw 1") { requestNewGame(drawCount: 1) }
                Button("New Game – Draw 3") { requestNewGame(drawCount: 3) }
            } label: {
                Label("New", systemImage: "plus.circle").toolbarHitArea()
            }
            .accessibilityIdentifier("newGame")
            .confirmationDialog(
                "Abandon this game?",
                isPresented: Binding(get: { pendingDrawCount != nil }, set: { if !$0 { pendingDrawCount = nil } }),
                titleVisibility: .visible,
                presenting: pendingDrawCount
            ) { drawCount in
                Button("Abandon and Deal", role: .destructive) {
                    withAnimation { model.newGame(drawCount: drawCount) }
                }
                .accessibilityIdentifier("abandon")
            } message: { _ in
                Text("It counts as a loss.")
            }

            Spacer(minLength: 0)
            status
            Spacer(minLength: 0)

            // Once every card is face up there is nothing to hint: Finish takes the hint's place.
            if model.game.canAutoComplete {
                Button {
                    Task { await model.autoComplete() }
                } label: {
                    Label("Finish", systemImage: "wand.and.stars").toolbarHitArea()
                }
                .accessibilityIdentifier("finish")
            } else {
                Button(action: showHint) {
                    Label("Hint", systemImage: "lightbulb").toolbarHitArea()
                }
                .disabled(model.isAutoCompleting || model.game.isWon)
                .accessibilityIdentifier("hint")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { model.undo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward").toolbarHitArea()
            }
            .disabled(!model.canUndo)
            .accessibilityIdentifier("undo")

            Menu {
                Button { sheet = .statistics } label: {
                    Label("Statistics…", systemImage: "chart.bar")
                }
                .accessibilityIdentifier("statistics")
                Button { sheet = .settings } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings")
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .toolbarHitArea()
            }
            .accessibilityIdentifier("more")
        }
        // Phones show icons only, so the toolbar fits in every language on a 320-point screen.
        .modifier(ToolbarLabels(showsTitles: horizontalSizeClass == .regular))
        .font(.body.weight(.medium))
        .foregroundColor(.white)
        .padding(.horizontal, horizontalSizeClass == .regular ? 16 : 8)
        .padding(.vertical, 2)
    }

    /// "Moves: 42 · 3:15"
    private var status: some View {
        HStack(spacing: 6) {
            Text("Moves: \(model.game.moveCount)")
                .accessibilityIdentifier("moves")
            if showTimer {
                Text(verbatim: "·").accessibilityHidden(true)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let time = GameTime.format(model.elapsed(at: context.date))
                    Text(verbatim: time)
                        .accessibilityLabel(Text("Time \(time)"))
                        .accessibilityIdentifier("timer")
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func requestNewGame(drawCount: Int) {
        if model.isInProgress {
            pendingDrawCount = drawCount
        } else {
            withAnimation { model.newGame(drawCount: drawCount) }
        }
    }

    private var felt: some View {
        RadialGradient(
            colors: [Color(red: 0.1, green: 0.5, blue: 0.28), Color(red: 0.03, green: 0.3, blue: 0.16)],
            center: .center,
            startRadius: 0,
            endRadius: 700
        )
    }
}

extension View {
    /// At least 44 × 44 points, Apple's minimum for something to tap.
    func toolbarHitArea() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

/// Titles next to the icons only where there is room (iPad), icons alone on phones.
private struct ToolbarLabels: ViewModifier {
    let showsTitles: Bool

    func body(content: Content) -> some View {
        if showsTitles {
            content.labelStyle(.titleAndIcon)
        } else {
            content.labelStyle(.iconOnly)
        }
    }
}

/// VoiceOver's "Move to foundation" / "Move to column N" actions.
private struct AccessibleMoves: ViewModifier {
    let moves: [AccessibleMove]
    let perform: (AccessibleMove) -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.accessibilityActions {
                ForEach(moves, id: \.name) { move in
                    Button(move.name) { perform(move) }
                }
            }
        } else if voiceOverEnabled {
            // iOS 15 has no builder for a varying number of actions, so they are chained. The chain's type
            // changes with the number of moves, which makes SwiftUI rebuild the card (a visible flicker
            // when it moves), so it is only built while VoiceOver is on.
            moves.reduce(AnyView(content)) { view, move in
                AnyView(view.accessibilityAction(named: Text(move.name)) { perform(move) })
            }
        } else {
            content
        }
    }
}

/// A short, fading side-to-side wobble as `progress` runs from 0 to 1.
private struct ShakeEffect: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = sin(progress * .pi * 6) * 7 * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}
