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

/// How a window's reset moment is written: as a clock time or date, as a
/// countdown, or both.
public enum ResetDisplay: String, CaseIterable, Codable, Sendable {
    case absolute
    case relative
    case both
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
    public var resetDisplay: ResetDisplay
    public var refreshInterval: RefreshInterval
    public var appLanguage: AppLanguage
    public var notificationsEnabled: Bool
    public var notifyFiveHourThresholds: [Int]
    public var notifyWeeklyThresholds: [Int]
    public var staleAfterMinutes: Int

    public static let defaults = ClaudePulseSettings(
        displayMode: .both,
        percentDisplay: .remaining,
        resetDisplay: .absolute,
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
        resetDisplay: ResetDisplay = .absolute,
        refreshInterval: RefreshInterval,
        appLanguage: AppLanguage = .system,
        notificationsEnabled: Bool,
        notifyFiveHourThresholds: [Int],
        notifyWeeklyThresholds: [Int],
        staleAfterMinutes: Int
    ) {
        self.displayMode = displayMode
        self.percentDisplay = percentDisplay
        self.resetDisplay = resetDisplay
        self.refreshInterval = refreshInterval
        self.appLanguage = appLanguage
        self.notificationsEnabled = notificationsEnabled
        self.notifyFiveHourThresholds = notifyFiveHourThresholds
        self.notifyWeeklyThresholds = notifyWeeklyThresholds
        self.staleAfterMinutes = staleAfterMinutes
    }

    /// Decoded field by field so that settings saved before a field existed still
    /// load, rather than failing outright and silently resetting everything.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ClaudePulseSettings.defaults
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        percentDisplay = try container.decodeIfPresent(PercentDisplay.self, forKey: .percentDisplay) ?? defaults.percentDisplay
        resetDisplay = try container.decodeIfPresent(ResetDisplay.self, forKey: .resetDisplay) ?? defaults.resetDisplay
        refreshInterval = try container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? defaults.appLanguage
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        notifyFiveHourThresholds = try container.decodeIfPresent([Int].self, forKey: .notifyFiveHourThresholds) ?? defaults.notifyFiveHourThresholds
        notifyWeeklyThresholds = try container.decodeIfPresent([Int].self, forKey: .notifyWeeklyThresholds) ?? defaults.notifyWeeklyThresholds
        staleAfterMinutes = try container.decodeIfPresent(Int.self, forKey: .staleAfterMinutes) ?? defaults.staleAfterMinutes
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
            resetDisplay: resetDisplay,
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
