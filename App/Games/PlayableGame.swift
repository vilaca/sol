import SolitaireCore
import SwiftUI

/// What the app needs from a game beyond its rules: its name, its board and its rule settings.
/// Everything else (cards, drag and tap, undo, timer, statistics, haptics, confetti, sheets, hints and the
/// no-moves alert) is shared and works through `SolitaireGame`. See docs/adding-a-game.md.
protocol PlayableGame: SolitaireGame {
    /// Shown in the New menu, Settings and Statistics. Proper names stay as they are ("FreeCell");
    /// descriptive ones are translated (`String(localized: "Spider")`).
    static var name: String { get }
    /// The rule options, shown in Settings. Each one also splits the statistics, and a variant also gets
    /// an entry per choice in the New menu. Default: none.
    static var ruleSettings: [RuleSetting] { get }
    /// Where each pile sits on the board.
    var board: BoardSpec { get }
    /// What VoiceOver calls a column or a free cell, e.g. "Column 3". Default: `Speech.pileName(_:)`.
    func spokenName(of pile: Pile) -> String
}

extension PlayableGame {
    static var ruleSettings: [RuleSetting] { [] }

    func spokenName(of pile: Pile) -> String { Speech.pileName(pile) }

    /// The statistics bucket for these options: the game, then each setting's choice, e.g. "klondike.draw-1".
    static func statisticsKey(for options: any GameOptions) -> String {
        ([kind.rawValue] + ruleSettings.map { "\($0.key)-\($0.choices[$0.choice(in: options)].key)" })
            .joined(separator: ".")
    }

    /// "Klondike – Draw 1", or "FreeCell" for a game without options. Settings that are not variants
    /// show their title too: "Golf – Wrap King and Ace: Off".
    static func title(for options: any GameOptions, variantsOnly: Bool = false) -> String {
        let parts = ruleSettings.filter { $0.isVariant || !variantsOnly }.map { setting in
            let choice = String(localized: setting.choices[setting.choice(in: options)].title)
            return setting.isVariant ? choice : String(localized: "\(String(localized: setting.title)): \(choice)", comment: "A rule option and its value, e.g. Recycle the waste: Twice")
        }
        return ([name] + parts).joined(separator: " – ")
    }

    static func deal(seed: UInt64, options: (any GameOptions)?) -> any PlayableGame {
        Self(seed: seed, options: options as? Options ?? Options())
    }

    static func decodeGame(_ data: Data) -> (any PlayableGame)? {
        try? decodeSaved(from: data)
    }

    static func decodeOptions(_ data: Data) -> any GameOptions {
        (try? Options.decodeSaved(from: data)) ?? Options()
    }

    static var defaultOptions: any GameOptions { Options() }
}

extension GameKind {
    /// The game type of each kind. A new game gets a case in `GameKind` and a line here.
    var type: any PlayableGame.Type {
        switch self {
        case .klondike: Klondike.self
        case .freeCell: FreeCell.self
        case .yukon: Yukon.self
        case .scorpion: Scorpion.self
        case .bakersDozen: BakersDozen.self
        case .eightOff: EightOff.self
        }
    }

    var name: String { type.name }
}

// MARK: - Rule settings

/// One rule option of a game, as Settings and Statistics show it: a toggle, or a choice of a few values.
/// Made with `.toggle` or `.picker` from a key path into the game's options.
struct RuleSetting: Identifiable {
    struct Choice {
        let title: LocalizedStringResource
        /// Names the choice in statistics keys: never change it.
        let key: String
    }

    let title: LocalizedStringResource
    /// Names the setting in statistics keys ("draw" in "klondike.draw-1"): never change it.
    let key: String
    let choices: [Choice]
    /// Chosen in the New menu, which lists every choice (Klondike's Draw 1 / Draw 3).
    let isVariant: Bool
    /// Shown as a switch in Settings; its choices are Off and On.
    private(set) var isToggle = false
    private let read: (any GameOptions) -> Int
    private let write: (any GameOptions, Int) -> any GameOptions

    var id: String { key }

    /// The index of the chosen choice.
    func choice(in options: any GameOptions) -> Int { read(options) }

    func setting(_ choice: Int, in options: any GameOptions) -> any GameOptions { write(options, choice) }

    static func toggle<Options: GameOptions>(
        _ title: LocalizedStringResource, _ keyPath: WritableKeyPath<Options, Bool>, key: String
    ) -> RuleSetting {
        var setting = picker(title, keyPath, key: key, choices: [(false, "Off", "off"), (true, "On", "on")])
        setting.isToggle = true
        return setting
    }

    static func picker<Options: GameOptions, Value: Equatable>(
        _ title: LocalizedStringResource,
        _ keyPath: WritableKeyPath<Options, Value>,
        key: String,
        isVariant: Bool = false,
        choices: [(value: Value, title: LocalizedStringResource, key: String)]
    ) -> RuleSetting {
        RuleSetting(
            title: title,
            key: key,
            choices: choices.map { Choice(title: $0.title, key: $0.key) },
            isVariant: isVariant,
            read: { options in
                guard let options = options as? Options else { return 0 }
                return choices.firstIndex { $0.value == options[keyPath: keyPath] } ?? 0
            },
            write: { options, choice in
                guard var options = options as? Options, choices.indices.contains(choice) else { return options }
                options[keyPath: keyPath] = choices[choice].value
                return options
            }
        )
    }
}

// MARK: - New menu

/// One entry of the New menu: a game, and for a game with variants, one of them.
struct GameChoice: Hashable, Identifiable {
    let kind: GameKind
    /// The chosen index of each variant setting, by setting key.
    let variant: [String: Int]

    /// Every entry, in menu order: "Klondike – Draw 1", "Klondike – Draw 3", "FreeCell", …
    static var all: [GameChoice] {
        GameKind.allCases.flatMap { kind in
            kind.type.ruleSettings.filter(\.isVariant).reduce([[String: Int]()]) { variants, setting in
                variants.flatMap { variant in setting.choices.indices.map { variant.merging([setting.key: $0]) { $1 } } }
            }
            .map { GameChoice(kind: kind, variant: $0) }
        }
    }

    /// Stable across languages, for UI tests: "new-klondike.draw-3".
    var id: String {
        "new-" + ([kind.rawValue] + settings.map { "\($0.key)-\($0.choices[variant[$0.key] ?? 0].key)" }).joined(separator: ".")
    }

    var title: String {
        kind.type.title(for: options(applyingTo: kind.type.defaultOptions), variantsOnly: true)
    }

    /// `options` with this entry's variant chosen.
    func options(applyingTo options: any GameOptions) -> any GameOptions {
        settings.reduce(options) { options, setting in setting.setting(variant[setting.key] ?? 0, in: options) }
    }

    /// Whether a game dealt with `options` is this variant.
    func matches(_ options: any GameOptions) -> Bool {
        settings.allSatisfy { $0.choice(in: options) == (variant[$0.key] ?? 0) }
    }

    private var settings: [RuleSetting] { kind.type.ruleSettings.filter(\.isVariant) }
}

// MARK: - The game in play

/// The game in play, whichever game it is. Equatable, so views can watch it change.
struct AnyGame: Equatable {
    private(set) var base: any PlayableGame

    init(_ base: any PlayableGame) {
        self.base = base
    }

    static func == (lhs: AnyGame, rhs: AnyGame) -> Bool {
        lhs.base.isEqual(to: rhs.base)
    }

    var kind: GameKind { type(of: base).kind }
    var options: any GameOptions { base.options }
    /// Where this game's result is counted: under the options it was dealt with.
    var statisticsKey: String { type(of: base).statisticsKey(for: base.options) }
    var board: BoardSpec { base.board }
    var piles: [Pile] { base.piles }
    var moveCount: Int { base.moveCount }
    var isWon: Bool { base.isWon }
    var canAutoComplete: Bool { base.canAutoComplete }
    var hint: Hint? { base.hint }
    var isStuck: Bool { base.isStuck }
    var pileByCard: [Int: Pile] { base.pileByCard }

    func cards(in pile: Pile) -> [Card] { base.cards(in: pile) }
    func canPickUp(from pile: Pile, at index: Int) -> Bool { base.canPickUp(from: pile, at: index) }
    func bestDestination(from pile: Pile, at index: Int) -> Pile? { base.bestDestination(from: pile, at: index) }
    func nextAutoMove() -> Move? { base.nextAutoMove() }

    mutating func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        base.move(from: source, at: index, to: destination)
    }

    mutating func apply(_ move: Move) -> Bool { base.apply(move) }

    mutating func draw() -> Bool { base.draw() }
}
