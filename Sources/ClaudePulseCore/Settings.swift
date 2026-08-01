import Foundation

public enum PercentDisplay: String, CaseIterable, Codable, Sendable {
    case remaining
    case used
    case both

    public var menuTitle: String {
        switch self {
        case .remaining:
            "Remaining"
        case .used:
            "Used"
        case .both:
            "Remaining and used"
        }
    }
}

public enum RefreshInterval: Int, CaseIterable, Codable, Sendable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    public var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    public var menuTitle: String {
        switch self {
        case .thirtySeconds:
            "30 seconds"
        case .oneMinute:
            "60 seconds"
        case .fiveMinutes:
            "5 minutes"
        }
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese

    public var localizationIdentifier: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        case .traditionalChinese:
            "zh-Hant"
        }
    }
}

public struct ClaudePulseSettings: Codable, Equatable, Sendable {
    private enum Keys {
        static let settings = "claudePulseSettings"
        static let legacyDisplayMode = "displayMode"
    }

    public var displayMode: DisplayMode
    public var percentDisplay: PercentDisplay
    public var refreshInterval: RefreshInterval
    public var appLanguage: AppLanguage
    public var notificationsEnabled: Bool
    public var notifyFiveHourThresholds: [Int]
    public var notifyWeeklyThresholds: [Int]
    public var staleAfterMinutes: Int

    public static let defaults = ClaudePulseSettings(
        displayMode: .both,
        percentDisplay: .remaining,
        refreshInterval: .oneMinute,
        appLanguage: .system,
        notificationsEnabled: false,
        notifyFiveHourThresholds: [20, 10, 5],
        notifyWeeklyThresholds: [20, 10, 5],
        staleAfterMinutes: 30
    )

    public init(
        displayMode: DisplayMode,
        percentDisplay: PercentDisplay,
        refreshInterval: RefreshInterval,
        appLanguage: AppLanguage = .system,
        notificationsEnabled: Bool,
        notifyFiveHourThresholds: [Int],
        notifyWeeklyThresholds: [Int],
        staleAfterMinutes: Int
    ) {
        self.displayMode = displayMode
        self.percentDisplay = percentDisplay
        self.refreshInterval = refreshInterval
        self.appLanguage = appLanguage
        self.notificationsEnabled = notificationsEnabled
        self.notifyFiveHourThresholds = notifyFiveHourThresholds
        self.notifyWeeklyThresholds = notifyWeeklyThresholds
        self.staleAfterMinutes = staleAfterMinutes
    }

    public static func load(from userDefaults: UserDefaults = .standard) -> ClaudePulseSettings {
        guard let data = userDefaults.data(forKey: Keys.settings),
              let decoded = try? JSONDecoder().decode(ClaudePulseSettings.self, from: data) else {
            var settings = ClaudePulseSettings.defaults
            if let rawDisplayMode = userDefaults.string(forKey: Keys.legacyDisplayMode),
               let displayMode = DisplayMode(rawValue: rawDisplayMode) {
                settings.displayMode = displayMode
            }
            return settings
        }
        return decoded.normalized()
    }

    public func save(to userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalized()) else {
            return
        }
        userDefaults.set(data, forKey: Keys.settings)
    }

    public func normalized() -> ClaudePulseSettings {
        ClaudePulseSettings(
            displayMode: displayMode,
            percentDisplay: percentDisplay,
            refreshInterval: refreshInterval,
            appLanguage: appLanguage,
            notificationsEnabled: notificationsEnabled,
            notifyFiveHourThresholds: Self.normalizedThresholds(notifyFiveHourThresholds),
            notifyWeeklyThresholds: Self.normalizedThresholds(notifyWeeklyThresholds),
            staleAfterMinutes: max(5, staleAfterMinutes)
        )
    }

    private static func normalizedThresholds(_ values: [Int]) -> [Int] {
        var normalized: [Int] = []
        for value in values.sorted(by: >) where (1...100).contains(value) {
            if normalized.last != value {
                normalized.append(value)
            }
        }
        return normalized
    }
}
