import SolitaireCore
import SwiftUI

/// The sheets opened from the toolbar's ⋯ menu.
enum MenuSheet: String, Identifiable {
    case statistics, settings, about
    /// The About page, shown once on first launch.
    case welcome
    var id: String { rawValue }
}

/// Statistics for one game with one set of options, picked at the top; opens on the game in play.
struct StatisticsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: GameKind
    /// The options whose statistics are shown.
    @State private var options: any GameOptions
    @State private var confirmingReset = false

    init(model: GameModel) {
        self.model = model
        _kind = State(initialValue: model.kind)
        _options = State(initialValue: model.game.options)
    }

    private var key: String { kind.type.statisticsKey(for: options) }
    private var stats: ModeStatistics { model.statistics[key] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Game", selection: Binding(get: { kind }, set: { show($0) })) {
                        ForEach(GameKind.allCases) { kind in
                            Text(verbatim: kind.name).tag(kind)
                        }
                    }
                    .accessibilityIdentifier("statisticsGame")
                    ForEach(kind.type.ruleSettings) { setting in
                        RuleSettingPicker(setting: setting, options: $options, segmentsVariants: true)
                            .accessibilityIdentifier("statistics-\(setting.key)")
                    }
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
            .confirmationDialog(
                Text("Reset the statistics of \(kind.type.title(for: options))?"),
                isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { model.resetStatistics(key) }
            } message: {
                Text("It can't be undone.")
            }
        }
    }

    /// Another game: shown with the options of its game in play, or those it is dealt with next.
    private func show(_ kind: GameKind) {
        self.kind = kind
        options = kind == model.kind ? model.game.options : model.preferredOptions(for: kind)
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

/// Picks one rule setting's value. With `segmentsVariants`, a variant shows as segments (its choices name
/// themselves, "Draw 1"); otherwise a picker with the setting's title.
private struct RuleSettingPicker: View {
    let setting: RuleSetting
    @Binding var options: any GameOptions
    var segmentsVariants = false

    var body: some View {
        let picker = Picker(selection: Binding(get: { setting.choice(in: options) }, set: { options = setting.setting($0, in: options) })) {
            ForEach(setting.choices.indices, id: \.self) { i in
                Text(setting.choices[i].title).tag(i)
            }
        } label: {
            Text(setting.title)
        }
        if segmentsVariants, setting.isVariant {
            picker.pickerStyle(.segmented)
        } else {
            picker
        }
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
                // One section per game with rule options.
                ForEach(GameKind.allCases.filter { !$0.type.ruleSettings.isEmpty }) { kind in
                    Section {
                        ForEach(kind.type.ruleSettings) { setting in
                            settingRow(setting, of: kind)
                                .accessibilityIdentifier("setting-\(kind.rawValue).\(setting.key)")
                        }
                    } header: {
                        Text(verbatim: kind.name)
                    } footer: {
                        Text("Applies from the next game.")
                    }
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

    @ViewBuilder
    private func settingRow(_ setting: RuleSetting, of kind: GameKind) -> some View {
        let options = Binding(get: { model.preferredOptions(for: kind) }, set: { model.setPreferredOptions($0, for: kind) })
        if setting.isToggle {
            Toggle(isOn: Binding(get: { setting.choice(in: options.wrappedValue) == 1 }, set: { options.wrappedValue = setting.setting($0 ? 1 : 0, in: options.wrappedValue) })) {
                Text(setting.title)
            }
        } else {
            RuleSettingPicker(setting: setting, options: options)
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
                        Text("Solitaire card games, free for everyone.")
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
