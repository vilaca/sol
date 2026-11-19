import SwiftUI

/// The sheets opened from the toolbar's ⋯ menu.
enum MenuSheet: String, Identifiable {
    case statistics, settings
    var id: String { rawValue }
}

struct StatisticsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var drawCount: Int
    @State private var confirmingReset = false

    init(model: GameModel) {
        self.model = model
        _drawCount = State(initialValue: model.game.drawCount)
    }

    private var stats: ModeStatistics { model.statistics[drawCount: drawCount] }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Deal", selection: $drawCount) {
                        Text("Draw 1").tag(1)
                        Text("Draw 3").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("statisticsMode")
                }
                Section("Games") {
                    row("Played", "\(stats.played)")
                    row("Won", "\(stats.won)")
                    row("Win rate", stats.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) })
                }
                Section("Streaks") {
                    row("Current streak", "\(stats.currentStreak)")
                    row("Best streak", "\(stats.bestStreak)")
                }
                Section("Best game") {
                    row("Best time", stats.bestTime.map(GameTime.format))
                    row("Fewest moves", stats.fewestMoves.map { "\($0)" })
                }
                Section {
                    Button("Reset Statistics", role: .destructive) { confirmingReset = true }
                        .accessibilityIdentifier("resetStatistics")
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("done")
                }
            }
            .confirmationDialog("Reset all statistics?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { model.resetStatistics() }
            } message: {
                Text("This clears the Draw 1 and Draw 3 statistics. It can't be undone.")
            }
        }
        .navigationViewStyle(.stack)
    }

    /// `nil` shows a dash: nothing recorded yet.
    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "—")
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.haptics) private var haptics = true
    @AppStorage(PreferenceKey.showTimer) private var showTimer = true

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Haptics", isOn: $haptics)
                        .accessibilityIdentifier("hapticsToggle")
                    Toggle("Show timer", isOn: $showTimer)
                        .accessibilityIdentifier("timerToggle")
                }
                Section {
                    Picker("Deal", selection: $model.preferredDrawCount) {
                        Text("Draw 1").tag(1)
                        Text("Draw 3").tag(3)
                    }
                } footer: {
                    Text("Applies from the next game.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("done")
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
