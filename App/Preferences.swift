import UIKit

/// UserDefaults keys for the settings sheet. Read with `@AppStorage` in views; every default is `true`.
enum PreferenceKey {
    static let haptics = "haptics"
    static let showTimer = "showTimer"

    static let all = [haptics, showTimer]
}

/// Taptic feedback for game events, off when the player turns Haptics off in Settings.
@MainActor
enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.haptics) as? Bool ?? true
    }

    static func pickUp() {
        impact(.light)
    }

    static func moved(toFoundation: Bool) {
        impact(toFoundation ? .medium : .soft)
    }

    static func rejected() {
        notify(.warning)
    }

    static func won() {
        notify(.success)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
