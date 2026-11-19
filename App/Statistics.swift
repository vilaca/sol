import Foundation

/// Results for one deal mode (draw 1 or draw 3). A game counts as played once it is won or abandoned.
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
    var drawOne = ModeStatistics()
    var drawThree = ModeStatistics()

    subscript(drawCount drawCount: Int) -> ModeStatistics {
        get { drawCount == 3 ? drawThree : drawOne }
        set {
            if drawCount == 3 { drawThree = newValue } else { drawOne = newValue }
        }
    }

    mutating func recordWin(drawCount: Int, time: TimeInterval, moves: Int) -> WinRecord {
        var mode = self[drawCount: drawCount]
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
        self[drawCount: drawCount] = mode
        return record
    }

    mutating func recordLoss(drawCount: Int) {
        self[drawCount: drawCount].played += 1
        self[drawCount: drawCount].currentStreak = 0
    }
}
