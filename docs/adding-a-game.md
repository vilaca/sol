# Adding a game

The checklist for adding a solitaire game to Sol. Follow it in order; you shouldn't need to read other files
than the ones it names. FreeCell (`FreeCell.swift`, `FreeCell+App.swift`) is the worked example to copy from.

## How the pieces fit

| Layer | What | Where |
|---|---|---|
| Rules | A value type conforming to `SolitaireGame`: piles, legal moves, win, hint, stuck check, options | `Packages/SolitaireCore/Sources/SolitaireCore/<Game>.swift` |
| Registry | A `GameKind` case (core) and a line in `GameKind.type` (app) | `Game.swift`, `App/Games/PlayableGame.swift` |
| App | `PlayableGame` conformance: name, rule settings, board layout, spoken pile names | `App/Games/<Game>+App.swift` |
| Shared | Board view, drag and tap, undo, timer, saves, statistics, haptics, confetti, sheets, hint button, no-moves alert, New menu | already done: `GameView`, `GameModel`, `BoardLayout`, `Speech`, `MenuSheets` |

What the shared code does with your game, so you know what to implement:

- **Tap** on a card that `canPickUp(from:at:)` allows: moves it to `bestDestination(from:at:)`, or shakes.
  **Drag**: drops on the pile `BoardLayout.pile(at:)` finds and calls `move(from:at:to:)`.
- **Tap on the stock** (a card or the empty `.stock` slot) calls `draw()`.
- **Hint button** shows `hint`: `.move(m)` outlines the cards and the destination, `.draw` outlines the stock.
  After every change, if `isStuck`, the "No moves left" alert offers Undo / New Game (once per dead end).
- **Finish** replaces Hint while `canAutoComplete`; it plays `nextAutoMove()` until `isWon`.
- **Saves**: one saved game per `GameKind` (`savedGame.<rawValue>`), restored when the player comes back to it.
- **Statistics**: one bucket per game and option combination, key `<rawValue>.<setting>-<choice>…`, e.g.
  `klondike.draw-1`, `golf.wrap-off`, `freecell`. Recorded under the options the game was dealt with.
- **New menu**: one entry per game, or per choice of its variant settings ("Klondike – Draw 1"). Picking
  another game resumes its saved game when it is the same variant, otherwise deals (asking first if that
  gives up a started game, which counts as a loss).
- **Settings**: one section per game with rule settings, built from `ruleSettings`.
- **VoiceOver**: labels and the "Move to …" actions come from `Speech`, using `spokenName(of:)` for pile names.
  A card is a VoiceOver element when it is face up in a `.tableau` pile, or the top card of any other pile.

## 1. Rules (core package)

Create `Packages/SolitaireCore/Sources/SolitaireCore/<Game>.swift`. Add the kind to `GameKind` in `Game.swift`
(the raw value is permanent: it names saves and statistics):

```swift
public enum GameKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case klondike
    case freeCell = "freecell"
    case golf               // new: raw value "golf"
```

Skeleton (piles you don't use simply aren't in `piles`; return `[]` for them in `cards(in:)`):

```swift
public struct GolfOptions: GameOptions {
    /// Every option is a stored property with its default. Older saves decode missing ones as the default.
    public var wrapsKingAndAce = false
    public init() {}
}

public struct Golf: SolitaireGame {
    public static let kind = GameKind.golf
    public static let tableauCount = 7

    public private(set) var stock: [Card]
    public private(set) var waste: [Card]
    public private(set) var tableau: [[Card]]
    public let options: GolfOptions          // saved with the game: a game keeps the rules it was dealt with
    public let seed: UInt64
    public private(set) var moveCount = 0

    public init(seed: UInt64, options: GolfOptions = GolfOptions()) {
        var rng = SplitMix64(seed: seed)
        var deck = Card.fullDeck              // face down; set isFaceUp where the deal shows a card
        deck.deterministicShuffle(using: &rng) // never the standard library's shuffle: deals must be stable
        …
    }

    /// For tests: any position.
    init(stock: [Card], waste: [Card], tableau: [[Card]], options: GolfOptions = GolfOptions(), seed: UInt64 = 0) { … }

    public var piles: [Pile] { [.stock, .waste] + (0..<Self.tableauCount).map(Pile.tableau) }
    public func cards(in pile: Pile) -> [Card] { … }          // bounds-checked: return [] for an unknown pile
    public var isWon: Bool { tableau.allSatisfy(\.isEmpty) }
    public var canAutoComplete: Bool { false }
    public func canMove(from source: Pile, at index: Int, to destination: Pile) -> Bool { … }  // never traps
    @discardableResult
    public mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        guard canMove(from: source, at: index, to: destination) else { return false }
        … // move the cards, flip what the rules flip, remove completed runs, …
        moveCount += 1
        return true
    }
    @discardableResult
    public mutating func draw() -> Bool { … moveCount += 1 … }  // only if the game has a stock
    public var hint: Hint? { … }
}
```

Requirements with a default in `Game.swift` (override only when the rule differs):

| Requirement | Default |
|---|---|
| `canPickUp(from:at:)` | a face-up card in a `.tableau` pile (with everything on it), or the top card elsewhere |
| `foundationDestination(from:at:)` | the first `.foundation` pile `canMove` accepts |
| `bestDestination(from:at:)` | foundation, then a non-empty column, then a free cell, then an empty column (not for a card already at the bottom of a column) |
| `nextAutoMove()` | the lowest-rank top card (any pile but stock and foundations) that has a foundation |
| `draw()` | does nothing (`false`) |
| `isStuck` | `!isWon && hint == nil` |
| `canApply`, `apply`, `pileByCard`, `isEqual(to:)`, `decodeSaved(from:)` | done; don't reimplement |

Rules notes:

- **Piles**: `.stock`, `.waste`, `.foundation(i)`, `.tableau(i)`, `.cell(i)`. One game's piles can mean something
  else in another: TriPeaks and Pyramid make every position a `.tableau(i)` pile of zero or one card. Add a
  `Pile` case only if nothing fits; then handle it in every `switch` over `Pile` (the compiler lists them).
- **Two decks**: `Card(suit:rank:isFaceUp:deck:)` with `deck` 0 or 1 (more copies when a game deals fewer suits: Spider's one
  suit is `deck` 0...7, see `Spider.swift`); `Card.id` is unique across both, so
  build the deck as `(0...1).flatMap { d in Card.fullDeck.map { Card(suit: $0.suit, rank: $0.rank, deck: d) } }`.
- **Runs that leave by themselves** (Scorpion, Spider): remove them inside `move` / `draw`, so one undo step
  covers both.
- **Pairs** (Pyramid): model "pair card A with card B" as `move(from: A, at: 0, to: B)`; `canMove` checks the
  sum, `move` sends both to the foundation. A king alone: `move(from: A, at: 0, to: .foundation(0))`.
- **Free cells and runs**: reuse `FreeCell.maxMovableRun(freeCells:emptyColumns:)` and `FreeCell.isRun(_:)`
  (alternating colours) or write the same-suit check next to it.
- **Hint**: a list of useful moves, best first, like `FreeCell.usefulMoves` or `Klondike.usefulMoves`
  (`Hint.swift`). Leave out moves that only shuffle cards back and forth, or the hint loops and the game is
  never "stuck". Return `.draw` when only the stock can help (`Klondike.stockCanHelp` shows how).
- **Stuck**: override `isStuck` only when "no hint" isn't the same as "can't win from here".

## 2. Core tests

`Packages/SolitaireCore/Tests/SolitaireCoreTests/<Game>Tests.swift`, Swift Testing, like `FreeCellTests.swift`:

- deal: pile counts, face up/down, 52 (or 104) distinct `id`s, same seed same deal;
- legal and illegal moves, including an illegal move changing nothing and a bad pile index not trapping;
- win (and `canAutoComplete` / `nextAutoMove` if the game finishes itself);
- hint priorities, one test each; a stuck position (`hint == nil`, `isStuck`); `freshDealsHaveMoves` over 50 seeds;
- each rule option: one test showing the rule changes with it;
- Codable round trip with `decodeSaved(from:)`, using a large seed (`.max`).

Gotchas: `#expect(game.move(…))` doesn't compile (assign to a `let` first); key paths as functions inside
`#expect` fail (`allSatisfy { $0.isFaceUp }`, not `allSatisfy(\.isFaceUp)`). Run:

```sh
swift test --package-path Packages/SolitaireCore
```

## 3. App conformance

Create `App/Games/<Game>+App.swift`:

```swift
import CoreGraphics
import SolitaireCore

extension Golf: PlayableGame {
    static var name: String { String(localized: "Golf") }   // proper names verbatim: { "TriPeaks" }

    /// Each rule option: one line. Keys name statistics buckets: never change them.
    static var ruleSettings: [RuleSetting] {
        [
            .toggle("Wrap King and Ace", \GolfOptions.wrapsKingAndAce, key: "wrap"),   // golf.wrap-off / golf.wrap-on
        ]
    }

    var board: BoardSpec {
        BoardSpec(columns: 7, spots: (0..<Self.tableauCount).map { PileSpot(.tableau($0), x: CGFloat($0), y: 0, fan: .down) } + [
            PileSpot(.stock, x: 0, y: 3, slot: .symbol("arrow.counterclockwise"), isDropTarget: false),
            PileSpot(.waste, x: 1, y: 3, fan: .stacked),
        ])
    }
}
```

and register it in `App/Games/PlayableGame.swift`:

```swift
var type: any PlayableGame.Type {
    switch self {
    case .klondike: Klondike.self
    case .freeCell: FreeCell.self
    case .golf: Golf.self
    }
}
```

`ruleSettings` entries:

- `.toggle(title, \Options.flag, key:)` — a switch in Settings; statistics `<key>-off` / `<key>-on`.
- `.picker(title, \Options.value, key:, choices: [(value, "Title", "choiceKey"), …])` — a picker in Settings;
  statistics `<key>-<choiceKey>`. Example: Pyramid's
  `.picker("Recycle the waste", \PyramidOptions.recycles, key: "recycle", choices: [(0, "Never", "never"), (1, "Once", "once"), (2, "Twice", "twice"), (-1, "Always", "always")])`.
- `isVariant: true` on a picker makes it a **variant**: each choice gets its own New-menu entry
  ("Spider – 2 suits") and a segmented control in Statistics. Spider:
  `.picker("Suits", \SpiderOptions.suits, key: "suits", isVariant: true, choices: [(1, "1 suit", "1"), (2, "2 suits", "2"), (4, "4 suits", "4")])`.
  Variant choice titles must name themselves ("Draw 1", "2 suits"); other settings show as "Title: Choice".
- The default of each option is the value in `Options()`; take the step's *(default)* there.

**Adding an option to an existing game is two lines**: the stored property in its options struct, and its
`ruleSettings` row. For FreeCell:

```swift
public struct FreeCellOptions: GameOptions {
    public var kingsOnly = false                     // 1
    public init() {}
}
// FreeCell+App.swift
static var ruleSettings: [RuleSetting] { [.toggle("Empty columns take kings only", \FreeCellOptions.kingsOnly, key: "kings")] }  // 2
```

then use `options.kingsOnly` in the rules and add the strings (step 5). Caveat: that renames the game's
statistics keys (`freecell` → `freecell.kings-off`); for a game players already have results in, map the old
key in `Statistics.init(from:)` (as `drawOne` → `klondike.draw-1`) and test it.

### Board layout (`BoardSpec`, in `App/BoardLayout.swift`)

- `columns`: board width in card columns. Above 7, cards get narrower (aspect 1.55) and the corner index
  bigger (`indexScale`), so 10 columns still fit a phone; check the iPhone SE screenshot. Never scroll sideways.
- `heightInCards` (default 5.5): on wide screens the card size is capped so this many card heights fit.
- `PileSpot(pile, x:, y:, fan:, slot:, isDropTarget:)`: `x` in column steps, `y` in row steps (row 0 is the top
  row; one row step is a card height plus two spacings). Fractions are fine: half-overlapping peaks and
  pyramids use `x: 1.5`, `y: 0.5`. `fan`: `.stacked`, `.down` (a column, squeezed to stop above the next spot
  below it in the same column, or the bottom of the board), `.right(visible: n)` (Klondike's waste).
  `slot`: the empty-pile outline, `.blank`, `.text("K")`, `.symbol("arrow.counterclockwise")`, or `nil` for none.
- Two rows of columns (Baker's Dozen 7 + 6): put the second row's spots at e.g. `y: 2.6`; the first row's
  columns then squeeze to end above them.
- Spot order is VoiceOver's reading order and the drawing order: stock, waste, foundations, cells, columns.
- Drops: `pile(at:)` takes the spot in the dropped card's column with the lowest row starting above the
  point; a spot with `isDropTarget: false` refuses the drop.

### Spoken names

Override `func spokenName(of pile: Pile) -> String` when "Column 3" / "Free cell 2" is wrong for your game,
e.g. TriPeaks: "Peak 2, row 3" for `.tableau(i)`. If cards other than face-up column cards or top cards should
(not) be VoiceOver elements, that rule is `isAccessible` in `GameView.cardView`; keep Klondike's behaviour.
"moved to …" uses `Speech.place` (columns and cells by name, everything else "foundation"): add a case there
if the game moves cards to the waste (Golf, TriPeaks).

## 4. App tests

- `AppTests/GamesTests.swift`: add the entries to `testNewMenuListsEveryGameAndVariant`, and the keys to
  `testStatisticsKeysNameTheGameAndItsOptions` (one per option combination).
- If you override `spokenName(of:)` or add a `Speech` case, test the label like `testFreeCellLabels`.

## 5. Strings, in all six languages

Add every new user-facing string (game name if descriptive, setting titles, choice titles, spoken labels) to
`T` in `scripts/translations.py`, with pt-PT, es, fr, de (and `br=` when pt-BR differs). Proper names
(Klondike, Yukon, FreeCell, TriPeaks, Baker's Dozen, Eight Off) need no row. Then:

```sh
python3 scripts/translations.py
```

After a build, check that every string the compiler extracted is in the catalog (the "Facts" snippet of the plan,
or):

```sh
python3 - <<'EOF'
import json,glob
d=".build/DerivedData/Build/Intermediates.noindex/Sol.build/Debug-iphonesimulator/Sol.build/Objects-normal/arm64/"
keys={e["key"] for f in glob.glob(d+"*.stringsdata") for t in json.load(open(f)).get("tables",{}).values() for e in t}
cat=set(json.load(open("App/Localizable.xcstrings"))["strings"])
print("missing:", sorted(keys-cat)); print("unused:", sorted(cat-keys))
EOF
```

Both lists must be empty. Interpolated Ints are `%lld`, Strings `%@`; plurals are `(one, other)` tuples.

## 6. UI smoke test

In `AppUITests/SolUITests.swift`, copy `testFreeCellDealMoveAndUndo`: open the New menu with
`tapMenu("newGame")`, tap the entry by its identifier (`new-<statistics key without options>`, e.g.
`new-golf`, `new-spider.suits-2`), make one move by tapping a card (`card-<id>`; find the seed-42 deal with a
throwaway `print` in a core test), check `Moves: 1`, undo, check `Moves: 0`. Empty piles are found as
`app.descendants(matching: .any)["tableau-3"]` (`stock-empty`, `foundation-0`, `cell-1`); prefer checking a
VoiceOver label (`app.buttons["Column 5, 10 of spades"]`) over frames, which may still be animating.

A screenshot to check the layout: `scripts/simulator.sh -game golf -seed 42 -reset`, then
`xcrun simctl io <udid> screenshot out.png` (`<udid>`: `scripts/simulator.sh --destination`).

## 7. Generate, test, document

```sh
xcodegen generate                                   # new files need it
swift test --package-path Packages/SolitaireCore
scripts/test-app.sh -skip-testing:SolUITests/SolUITests/testLaunchPerformance
```

Add the game to the list at the top of `README.md`.
