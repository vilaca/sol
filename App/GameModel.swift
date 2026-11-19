import SolitaireCore
import SwiftUI

/// Options read from the launch arguments, so UI tests get a known deal and a clean slate.
struct LaunchOptions {
    /// `-seed <n>`: deal this seed instead of a random one.
    var seed: UInt64?
    /// `-reset`: ignore and clear any saved game, settings and statistics.
    var reset = false
    /// `-game <kind>`: play this game (e.g. `freecell`) instead of the last one played.
    var game: GameKind?

    static var current: LaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        var options = LaunchOptions()
        options.seed = value("-seed").flatMap { UInt64($0) }
        options.reset = arguments.contains("-reset")
        options.game = value("-game").flatMap(GameKind.init(rawValue:))
        return options
    }
}

/// Play time of the current game, saved with it.
private struct GameClock: Codable {
    /// Time played before `GameModel.runningSince`.
    var accumulated: TimeInterval = 0
    /// Set by the first move. A started game counts as played; abandoning it is a loss.
    var isStarted = false
}

/// Owns the current game, undo history, play time, statistics and on-device persistence.
/// Each game keeps its own saved game, so switching games and back resumes where the player left off.
/// Nothing leaves the device.
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var game: AnyGame
    /// Cards that moved in the last change; drawn above the rest so they never slide under other cards.
    @Published private(set) var movedCards: Set<Int> = []
    @Published private(set) var isAutoCompleting = false
    @Published private(set) var statistics: Statistics
    /// What the current game's win achieved; `nil` until it is won.
    @Published private(set) var lastWin: WinRecord?
    /// The options each game is dealt with next: its settings, with the variant last chosen in the New menu.
    @Published private var preferredOptions: [GameKind: any GameOptions]

    private var history: [AnyGame] = []
    /// Bumped by every new deal, so a running autocomplete stops instead of playing into the next game.
    private var deal = 0
    private var clock = GameClock()
    /// When the clock last started running; `nil` while it is stopped.
    private var runningSince: Date?
    private var isPaused = false
    private let defaults: UserDefaults
    private let fixedSeed: UInt64?
    private let now: () -> Date

    private static let currentGameKey = "currentGame"
    private static let statisticsKey = "statistics"
    /// Klondike's deal mode, as saved before games had options.
    private static let legacyDrawCountKey = "drawCount"

    /// Klondike keeps the keys it had before Sol had other games, so its saved game survives the update.
    private static func saveKey(_ kind: GameKind) -> String {
        kind == .klondike ? "savedGame" : "savedGame.\(kind.rawValue)"
    }

    private static func clockKey(_ kind: GameKind) -> String {
        kind == .klondike ? "savedClock" : "savedClock.\(kind.rawValue)"
    }

    private static func optionsKey(_ kind: GameKind) -> String {
        "options.\(kind.rawValue)"
    }

    init(launch: LaunchOptions = LaunchOptions(), defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        fixedSeed = launch.seed
        if launch.reset {
            let keys = [Self.currentGameKey, Self.statisticsKey, Self.legacyDrawCountKey]
                + GameKind.allCases.flatMap { [Self.saveKey($0), Self.clockKey($0), Self.optionsKey($0)] }
            for key in keys + PreferenceKey.all {
                defaults.removeObject(forKey: key)
            }
            // A clean slate for tests, so they start on the board rather than on the welcome page.
            defaults.set(true, forKey: PreferenceKey.hasSeenWelcome)
        }
        statistics = defaults.data(forKey: Self.statisticsKey).flatMap { try? JSONDecoder().decode(Statistics.self, from: $0) } ?? Statistics()
        let preferredOptions = Self.loadOptions(from: defaults)
        self.preferredOptions = preferredOptions
        let kind = launch.game ?? defaults.string(forKey: Self.currentGameKey).flatMap(GameKind.init(rawValue:)) ?? .klondike
        if launch.seed == nil, let saved = Self.loadSaved(kind, from: defaults), !saved.game.isWon {
            game = saved.game
            clock = saved.clock
        } else {
            game = AnyGame(kind.type.deal(seed: launch.seed ?? .random(in: .min ... .max), options: preferredOptions[kind]))
        }
        defaults.set(kind.rawValue, forKey: Self.currentGameKey)
        updateClock()
    }

    var kind: GameKind { game.kind }

    var canUndo: Bool { !history.isEmpty && !isAutoCompleting && !game.isWon }

    /// Started and not yet won: dealing again now counts as a loss.
    var isInProgress: Bool { clock.isStarted && !game.isWon }

    /// Play time so far.
    func elapsed(at date: Date? = nil) -> TimeInterval {
        clock.accumulated + (runningSince.map { (date ?? now()).timeIntervalSince($0) } ?? 0)
    }

    /// Stops the clock while the app is in the background or a sheet covers the game.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        updateClock()
        save()
    }

    // MARK: - New games

    /// Deals the current game again, with the player's options. Abandoning a started game records a loss.
    func newGame() {
        if isInProgress { recordStatistics { $0.recordLoss(key: game.statisticsKey) } }
        start(AnyGame(kind.type.deal(seed: fixedSeed ?? .random(in: .min ... .max), options: preferredOptions(for: kind))), clock: GameClock())
    }

    /// Plays the game picked in the New menu, remembering its variant. Another game's saved game resumes
    /// when it is the same variant; otherwise a new one is dealt. The game being left stays saved.
    func newGame(_ choice: GameChoice) {
        setPreferredOptions(choice.options(applyingTo: preferredOptions(for: choice.kind)), for: choice.kind)
        guard choice.kind != kind else { return newGame() }
        save()
        let saved = Self.loadSaved(choice.kind, from: defaults)
        if let saved, !saved.game.isWon, choice.matches(saved.game.options) {
            start(saved.game, clock: saved.clock)
            return
        }
        if let saved, saved.clock.isStarted, !saved.game.isWon {
            recordStatistics { $0.recordLoss(key: saved.game.statisticsKey) }
        }
        let options = preferredOptions(for: choice.kind)
        start(AnyGame(choice.kind.type.deal(seed: fixedSeed ?? .random(in: .min ... .max), options: options)), clock: GameClock())
    }

    /// Whether `newGame(choice)` would give up a started game, which counts as a loss.
    func abandons(_ choice: GameChoice) -> Bool {
        if choice.kind == kind { return isInProgress }
        guard let saved = Self.loadSaved(choice.kind, from: defaults), saved.clock.isStarted, !saved.game.isWon else { return false }
        return !choice.matches(saved.game.options)
    }

    // MARK: - Options and statistics

    /// The options `kind` is dealt with next.
    func preferredOptions(for kind: GameKind) -> any GameOptions {
        preferredOptions[kind] ?? kind.type.defaultOptions
    }

    /// Applies from the next deal: a game in progress keeps the options it was dealt with.
    func setPreferredOptions(_ options: any GameOptions, for kind: GameKind) {
        preferredOptions[kind] = options
        if let data = try? JSONEncoder().encode(options) {
            defaults.set(data, forKey: Self.optionsKey(kind))
        }
    }

    /// Clears one statistics bucket; by default the current game's.
    func resetStatistics(_ key: String? = nil) {
        let key = key ?? game.statisticsKey
        recordStatistics { $0.reset(key) }
    }

    // MARK: - Play

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        replace(game, with: previous)
    }

    @discardableResult
    func draw() -> Bool {
        apply { $0.draw() }
    }

    @discardableResult
    func move(from source: Pile, at index: Int, to destination: Pile) -> Bool {
        apply { $0.move(from: source, at: index, to: destination) }
    }

    func autoComplete() async {
        guard !isAutoCompleting else { return }
        isAutoCompleting = true
        defer { isAutoCompleting = false }
        let deal = deal
        while deal == self.deal, let next = game.nextAutoMove() {
            withAnimation(.easeInOut(duration: 0.18)) {
                _ = apply { $0.apply(next) }
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
    }

    // MARK: - Private

    private func start(_ newGame: AnyGame, clock: GameClock) {
        deal += 1
        history = []
        movedCards = []
        lastWin = nil
        self.clock = clock
        runningSince = nil
        game = newGame
        defaults.set(newGame.kind.rawValue, forKey: Self.currentGameKey)
        updateClock()
        save()
    }

    @discardableResult
    private func apply(_ change: (inout AnyGame) -> Bool) -> Bool {
        var next = game
        guard change(&next) else { return false }
        history.append(game)
        clock.isStarted = true
        replace(game, with: next)
        return true
    }

    private func replace(_ old: AnyGame, with new: AnyGame) {
        let before = old.pileByCard
        movedCards = Set(new.pileByCard.filter { before[$0.key] != $0.value }.keys)
        game = new
        updateClock()
        if new.isWon, !old.isWon {
            let time = elapsed()
            let moves = new.moveCount
            var record: WinRecord?
            recordStatistics { record = $0.recordWin(key: new.statisticsKey, time: time, moves: moves) }
            lastWin = record
        }
        save()
    }

    /// Runs the clock only while a started, unwon game is on screen.
    private func updateClock() {
        let shouldRun = clock.isStarted && !game.isWon && !isPaused
        if shouldRun, runningSince == nil {
            runningSince = now()
        } else if !shouldRun, let since = runningSince {
            clock.accumulated += now().timeIntervalSince(since)
            runningSince = nil
        }
    }

    private func recordStatistics(_ change: (inout Statistics) -> Void) {
        change(&statistics)
        if let data = try? JSONEncoder().encode(statistics) {
            defaults.set(data, forKey: Self.statisticsKey)
        }
    }

    private func save() {
        var saved = clock
        saved.accumulated = elapsed()
        if let data = try? JSONEncoder().encode(game.base), let clockData = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.saveKey(kind))
            defaults.set(clockData, forKey: Self.clockKey(kind))
        }
    }

    private static func loadSaved(_ kind: GameKind, from defaults: UserDefaults) -> (game: AnyGame, clock: GameClock)? {
        guard let data = defaults.data(forKey: saveKey(kind)), let game = kind.type.decodeGame(data) else { return nil }
        let clock = defaults.data(forKey: clockKey(kind)).flatMap { try? JSONDecoder().decode(GameClock.self, from: $0) } ?? GameClock()
        return (AnyGame(game), clock)
    }

    private static func loadOptions(from defaults: UserDefaults) -> [GameKind: any GameOptions] {
        var result: [GameKind: any GameOptions] = [:]
        for kind in GameKind.allCases {
            if let data = defaults.data(forKey: optionsKey(kind)) {
                result[kind] = kind.type.decodeOptions(data)
            }
        }
        if result[.klondike] == nil, defaults.object(forKey: legacyDrawCountKey) != nil {
            result[.klondike] = KlondikeOptions(drawCount: defaults.integer(forKey: legacyDrawCountKey) == 3 ? 3 : 1)
        }
        return result
    }
}
