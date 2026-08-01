import ClaudePulseCore
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: ClaudePulseSettings {
        didSet {
            settings.save(to: userDefaults)
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = ClaudePulseSettings.load(from: userDefaults)
        L10n.useLanguage(settings.appLanguage)
    }

    func update(_ mutate: (inout ClaudePulseSettings) -> Void) {
        var next = settings
        mutate(&next)
        let normalized = next.normalized()
        L10n.useLanguage(normalized.appLanguage)
        settings = normalized
    }
}
