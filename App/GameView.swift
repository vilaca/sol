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
    /// The New-menu choice waiting for "Abandon this game?" to be confirmed.
    @State private var pendingChoice: GameChoice?
    /// The hint being shown; cleared after a moment or by the next move.
    @State private var hint: Hint?
    /// The first card of a pair (Pyramid), waiting for its partner.
    @State private var selected: PlacedCard?
    @State private var showsNoMoves = false
    /// "No moves left" was shown for the current dead end; asked again only after a way out appeared.
    @State private var warnedNoMoves = false
    @AppStorage(PreferenceKey.showTimer) private var showTimer = true
    @AppStorage(PreferenceKey.hasSeenWelcome) private var hasSeenWelcome = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let board = "board"

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                board(BoardLayout(size: geometry.size, board: model.game.board))
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
            case .about: AboutView()
            case .welcome: AboutView(isWelcome: true)
            }
        }
        .onAppear {
            if !hasSeenWelcome {
                hasSeenWelcome = true
                sheet = .welcome
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
            selected = nil
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
            let order = Dictionary(layout.board.spots.enumerated().map { ($1.pile, $0) }) { first, _ in first }
            ForEach(layout.place(model.game, raised: model.movedCards)) { placed in
                cardView(placed, order: order[placed.pile] ?? 0, layout)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.board)
        // VoiceOver reads the piles in the board's order, each column top to bottom (see `readingOrder`).
        .accessibilityElement(children: .contain)
    }

    private func slots(_ layout: BoardLayout) -> some View {
        let game = model.game
        return ForEach(Array(layout.board.spots.enumerated()), id: \.offset) { order, spot in
            if let mark = spot.slot {
                let isEmpty = game.cards(in: spot.pile).isEmpty
                let isHinted = spot.pile == .stock
                    ? hint == .draw && isEmpty
                    : isEmpty && hintDestination == spot.pile
                SlotView(size: layout.cardSize, mark: mark)
                    .modifier(HintGlow(isOn: isHinted, size: layout.cardSize))
                    .onTapGesture { if spot.pile == .stock { draw() } }
                    .accessibilityElement()
                    .accessibilityLabel(Speech.emptyLabel(spot.pile, of: game.base))
                    .accessibilityIdentifier(Self.slotIdentifier(spot.pile))
                    .accessibilityAddTraits(spot.pile == .stock ? .isButton : [])
                    .accessibilityHidden(!isEmpty)
                    .accessibilitySortPriority(Self.readingOrder(order, 0))
                    .position(layout.center(spot))
            }
        }
    }

    /// "stock-empty", "foundation-0", "tableau-3", "cell-1": what UI tests find empty piles by.
    private static func slotIdentifier(_ pile: Pile) -> String {
        switch pile {
        case .stock: "stock-empty"
        case .waste: "waste-empty"
        case .foundation(let i): "foundation-\(i)"
        case .tableau(let i): "tableau-\(i)"
        case .cell(let i): "cell-\(i)"
        }
    }

    private func cardView(_ placed: PlacedCard, order: Int, _ layout: BoardLayout) -> some View {
        let game = model.game
        let isDragged = drag.map { $0.pile == placed.pile && placed.index >= $0.index } ?? false
        let isShaking = shakeTarget.map { $0.pile == placed.pile && placed.index >= $0.index } ?? false
        let isTop = placed.index == game.cards(in: placed.pile).count - 1
        let isAccessible = if case .tableau = placed.pile { placed.card.isFaceUp } else { isTop }
        let label = isAccessible ? Speech.label(for: placed.card, in: placed.pile, at: placed.index, of: game.base) : nil
        // Not rebuilt on every drag frame: VoiceOver users don't drag.
        let moves = drag == nil && isAccessible && canDrag(placed) ? Speech.moves(from: placed.pile, at: placed.index, in: game.base) : []
        return CardView(
            card: placed.card,
            size: layout.cardSize,
            indexScale: layout.indexScale,
            accessibilityText: label,
            isHinted: isHinted(placed, isTop: isTop) || selected?.card.id == placed.card.id
        )
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
            .accessibilitySortPriority(Self.readingOrder(order, placed.index))
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
        Speech.announce(Speech.hint(next, in: model.game.base))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if hint == next { withAnimation(.easeInOut(duration: 0.4)) { hint = nil } }
        }
    }

    /// Says "No moves left" once per dead end, so drawing through a stuck stock doesn't ask again on every card.
    private func warnIfStuck(_ game: AnyGame) {
        guard !game.isWon, !model.isAutoCompleting else { return }
        if !game.isStuck {
            warnedNoMoves = false
        } else if !warnedNoMoves {
            warnedNoMoves = true
            showsNoMoves = true
            Speech.announce(Speech.noMovesLeft)
        }
    }

    /// Higher is read first: the piles in the order of the board's spots (stock, waste, foundations, then
    /// column 1 top to bottom, column 2, … for Klondike), each pile from its bottom card up.
    private static func readingOrder(_ spot: Int, _ index: Int) -> Double {
        Double(100_000 - spot * 200 - index)
    }

    private func canDrag(_ placed: PlacedCard) -> Bool {
        !model.isAutoCompleting && model.game.canPickUp(from: placed.pile, at: placed.index)
    }

    /// A tap sends the card to the best pile (a foundation first). With nowhere to go, it shakes.
    private func tap(_ placed: PlacedCard) {
        guard !model.isAutoCompleting, !model.game.isWon else { return }
        if placed.pile == .stock {
            draw()
        } else if canDrag(placed) {
            if model.game.kind.type.pairsCards {
                pair(placed)
            } else if let destination = model.game.bestDestination(from: placed.pile, at: placed.index) {
                _ = perform(placed, to: destination, animation: .easeInOut(duration: 0.2))
            } else {
                rejected()
                shake(placed)
            }
        }
    }

    /// Pyramid: a king goes by itself; any other card is picked first (tap it again to put it back) and then
    /// paired with the next card tapped, or with another card picked instead when the two don't fit.
    private func pair(_ placed: PlacedCard) {
        let animation = Animation.easeInOut(duration: 0.2)
        if let first = selected {
            if first.card.id == placed.card.id {
                selected = nil
                return
            }
            if perform(first, to: placed.pile, animation: animation) { return }
        }
        if let destination = model.game.bestDestination(from: placed.pile, at: placed.index) {
            _ = perform(placed, to: destination, animation: animation)
        } else if selected == nil {
            selected = placed
        } else {
            rejected()
            shake(placed)
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
                Speech.announce(Speech.moved(source[placed.index], to: destination, before: before.base, after: model.game.base, from: placed.pile))
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
        let drew = model.game.cards(in: .stock).isEmpty ? model.draw() : withAnimation(.easeInOut(duration: 0.2)) { model.draw() }
        if drew { Speech.announce(Speech.drew(model.game.base)) }
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
                ForEach(GameChoice.all) { choice in
                    Button(choice.title) { requestNewGame(choice) }
                        .accessibilityIdentifier(choice.id)
                }
            } label: {
                Label("New", systemImage: "plus.circle").toolbarHitArea()
            }
            .accessibilityIdentifier("newGame")
            .confirmationDialog(
                "Abandon this game?",
                isPresented: Binding(get: { pendingChoice != nil }, set: { if !$0 { pendingChoice = nil } }),
                titleVisibility: .visible,
                presenting: pendingChoice
            ) { choice in
                Button("Abandon and Deal", role: .destructive) {
                    withAnimation { model.newGame(choice) }
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
                Button { sheet = .about } label: {
                    Label("About Sol…", systemImage: "info.circle")
                }
                .accessibilityIdentifier("about")
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

    private func requestNewGame(_ choice: GameChoice) {
        if model.abandons(choice) {
            pendingChoice = choice
        } else {
            withAnimation { model.newGame(choice) }
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

/// VoiceOver's "Move to foundation" / "Move to column N" actions. Built with `ForEach`, so the view keeps
/// its identity as the number of moves changes (chaining modifiers through `AnyView` made cards flicker).
private struct AccessibleMoves: ViewModifier {
    let moves: [AccessibleMove]
    let perform: (AccessibleMove) -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(moves, id: \.name) { move in
                Button(move.name) { perform(move) }
            }
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
