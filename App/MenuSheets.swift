import SwiftUI

/// The sheets opened from the toolbar's ⋯ menu.
enum MenuSheet: String, Identifiable {
    case statistics, settings, about
    /// The About page, shown once on first launch.
    case welcome
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
        NavigationStack {
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
        NavigationStack {
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
    }
}

/// What Sol promises, with links to the code and the privacy policy. Also shown once, on first launch.
struct AboutView: View {
    /// First launch: titled as a welcome, closed with Play.
    var isWelcome = false
    @Environment(\.dismiss) private var dismiss

    static let repository = URL(string: "https://github.com/vilaca/sol")!
    static let privacyPolicy = URL(string: "https://github.com/vilaca/sol/blob/main/PRIVACY.md")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(red: 1, green: 0.8, blue: 0.35))
                            .frame(width: 84, height: 84)
                            .background(Circle().fill(Color(red: 0.07, green: 0.17, blue: 0.4)))
                            .accessibilityHidden(true)
                        Text(verbatim: "Sol").font(.largeTitle.bold())
                        Text("Klondike solitaire, free for everyone.")
                            .multilineTextAlignment(.center)
                        Text("Version \(version)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Our promise") {
                    Label("100% free: no pay to play, no pay to win", systemImage: "gift")
                    Label("No ads", systemImage: "nosign")
                    Label("No in-app purchases", systemImage: "cart.badge.minus")
                    Label("No tracking, no analytics, no account", systemImage: "eye.slash")
                    Label("Works offline: nothing leaves your device", systemImage: "wifi.slash")
                }
                Section {
                    Link(destination: Self.repository) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .accessibilityIdentifier("repositoryLink")
                    Link(destination: Self.privacyPolicy) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                } footer: {
                    Text("Sol is open source under the MIT license: anyone can read the code, check these promises and help improve it.")
                }
            }
            .navigationTitle(isWelcome ? Text("Welcome to Sol") : Text("About"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { isWelcome ? Text("Play") : Text("Done") }
                        .accessibilityIdentifier("done")
                }
            }
        }
    }
}
