import Foundation

/// Results for one game with one set of options (Klondike draw 1, say). A game counts as played once it is
/// won or abandoned.
struct ModeStatistics: Codable, Equatable {
    var played = 0
    var won = 0
    var currentStreak = 0
    var bestStreak = 0
    /// Wins only.
    var bestTime: TimeInterval?
    /// Wins only.
    var fewestMoves: Int?

    var winRate: Double? {
        played == 0 ? nil : Double(won) / Double(played)
    }
}

/// What a win achieved, for the win banner.
struct WinRecord: Equatable {
    let time: TimeInterval
    let moves: Int
    /// Beat an earlier best; a first win is not announced as a record.
    let isBestTime: Bool
    let isFewestMoves: Bool
}

/// Game statistics, kept on the device only (one JSON value in UserDefaults).
struct Statistics: Codable, Equatable {
    /// By game and options, e.g. "klondike.draw-1" or "freecell" (see `PlayableGame.statisticsKey`).
    private(set) var modes: [String: ModeStatistics] = [:]

    init() {}

    subscript(key: String) -> ModeStatistics {
        get { modes[key] ?? ModeStatistics() }
        set { modes[key] = newValue }
    }

    mutating func recordWin(key: String, time: TimeInterval, moves: Int) -> WinRecord {
        var mode = self[key]
        let record = WinRecord(
            time: time,
            moves: moves,
            isBestTime: mode.bestTime.map { time < $0 } ?? false,
            isFewestMoves: mode.fewestMoves.map { moves < $0 } ?? false
        )
        mode.played += 1
        mode.won += 1
        mode.currentStreak += 1
        mode.bestStreak = max(mode.bestStreak, mode.currentStreak)
        mode.bestTime = min(mode.bestTime ?? time, time)
        mode.fewestMoves = min(mode.fewestMoves ?? moves, moves)
        self[key] = mode
        return record
    }

    mutating func recordLoss(key: String) {
        self[key].played += 1
        self[key].currentStreak = 0
    }

    mutating func reset(_ key: String) {
        modes[key] = nil
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case modes
        /// Klondike's two modes, as saved before Sol had other games.
        case drawOne, drawThree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modes = try container.decodeIfPresent([String: ModeStatistics].self, forKey: .modes) ?? [:]
        for (key, legacy) in [("klondike.draw-1", CodingKeys.drawOne), ("klondike.draw-3", .drawThree)] {
            if let mode = try container.decodeIfPresent(ModeStatistics.self, forKey: legacy), mode != ModeStatistics() {
                modes[key] = mode
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modes, forKey: .modes)
    }
}
