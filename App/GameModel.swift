import SolitaireCore
import SwiftUI

/// Options read from the launch arguments, so UI tests get a known deal and a clean slate.
struct LaunchOptions {
    /// `-seed <n>`: deal this seed instead of a random one.
    var seed: UInt64?
    /// `-reset`: ignore and clear any saved game, settings and statistics.
    var reset = false

    static var current: LaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        var options = LaunchOptions()
        if let i = arguments.firstIndex(of: "-seed"), i + 1 < arguments.count {
            options.seed = UInt64(arguments[i + 1])
        }
        options.reset = arguments.contains("-reset")
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
/// Nothing leaves the device.
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var game: Klondike
    /// Cards that moved in the last change; drawn above the rest so they never slide under other cards.
    @Published private(set) var movedCards: Set<Int> = []
    @Published private(set) var isAutoCompleting = false
    @Published private(set) var statistics: Statistics
    /// What the current game's win achieved; `nil` until it is won.
    @Published private(set) var lastWin: WinRecord?
    /// Deal mode for the next new game.
    @Published var preferredDrawCount: Int {
        didSet { defaults.set(preferredDrawCount, forKey: Self.drawCountKey) }
    }

    private var history: [Klondike] = []
    /// Bumped by every new deal, so a running autocomplete stops instead of playing into the next game.
    private var deal = 0
    private var clock = GameClock()
    /// When the clock last started running; `nil` while it is stopped.
    private var runningSince: Date?
    private var isPaused = false
    private let defaults: UserDefaults
    private let fixedSeed: UInt64?
    private let now: () -> Date

    private static let saveKey = "savedGame"
    private static let clockKey = "savedClock"
    private static let drawCountKey = "drawCount"
    private static let statisticsKey = "statistics"

    init(launch: LaunchOptions = LaunchOptions(), defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        fixedSeed = launch.seed
        if launch.reset {
            for key in [Self.saveKey, Self.clockKey, Self.drawCountKey, Self.statisticsKey] + PreferenceKey.all {
                defaults.removeObject(forKey: key)
            }
            // A clean slate for tests, so they start on the board rather than on the welcome page.
            defaults.set(true, forKey: PreferenceKey.hasSeenWelcome)
        }
        statistics = defaults.data(forKey: Self.statisticsKey).flatMap { try? JSONDecoder().decode(Statistics.self, from: $0) } ?? Statistics()
        let drawCount = defaults.integer(forKey: Self.drawCountKey) == 3 ? 3 : 1
        preferredDrawCount = drawCount
        if launch.seed == nil,
           let data = defaults.data(forKey: Self.saveKey),
           let saved = try? JSONDecoder().decode(Klondike.self, from: data),
           !saved.isWon {
            game = saved
            clock = defaults.data(forKey: Self.clockKey).flatMap { try? JSONDecoder().decode(GameClock.self, from: $0) } ?? GameClock()
        } else {
            game = Klondike(seed: launch.seed ?? .random(in: .min ... .max), drawCount: drawCount)
        }
        updateClock()
    }

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

    /// Deals a new game. Abandoning a started game records a loss.
    func newGame(drawCount: Int? = nil) {
        if let drawCount { preferredDrawCount = drawCount }
        if isInProgress { recordStatistics { $0.recordLoss(drawCount: game.drawCount) } }
        deal += 1
        history = []
        movedCards = []
        lastWin = nil
        clock = GameClock()
        runningSince = nil
        game = Klondike(seed: fixedSeed ?? .random(in: .min ... .max), drawCount: preferredDrawCount)
        save()
    }

    func resetStatistics() {
        recordStatistics { $0 = Statistics() }
    }

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

    @discardableResult
    private func apply(_ change: (inout Klondike) -> Bool) -> Bool {
        var next = game
        guard change(&next) else { return false }
        history.append(game)
        clock.isStarted = true
        replace(game, with: next)
        return true
    }

    private func replace(_ old: Klondike, with new: Klondike) {
        let before = old.pileByCard
        movedCards = Set(new.pileByCard.filter { before[$0.key] != $0.value }.keys)
        game = new
        updateClock()
        if new.isWon, !old.isWon {
            let time = elapsed()
            let moves = new.moveCount
            var record: WinRecord?
            recordStatistics { record = $0.recordWin(drawCount: new.drawCount, time: time, moves: moves) }
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
        if let data = try? JSONEncoder().encode(game), let clockData = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.saveKey)
            defaults.set(clockData, forKey: Self.clockKey)
        }
    }
}
