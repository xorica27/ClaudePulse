import ClaudePulseCore
import Foundation

@MainActor
enum L10n {
    private static var overrideLanguage: AppLanguage = .system

    static func useLanguage(_ language: AppLanguage) {
        overrideLanguage = language
    }

    static func text(_ key: String) -> String {
        let mainValue = preferredBundle(in: .main)?.localizedString(forKey: key, value: nil, table: nil)
            ?? Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if mainValue != key {
            return mainValue
        }

        #if SWIFT_PACKAGE
        let moduleValue = preferredBundle(in: .module)?.localizedString(forKey: key, value: nil, table: nil)
            ?? Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        if moduleValue != key {
            return moduleValue
        }
        #endif

        return key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static func appLanguageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            text("appLanguage.system")
        case .english:
            text("appLanguage.english")
        case .simplifiedChinese:
            text("appLanguage.simplifiedChinese")
        case .traditionalChinese:
            text("appLanguage.traditionalChinese")
        }
    }

    static func displayModeTitle(_ mode: DisplayMode) -> String {
        switch mode {
        case .both:
            text("displayMode.both")
        case .fiveHour:
            text("displayMode.fiveHour")
        case .weekly:
            text("displayMode.weekly")
        }
    }

    static func percentDisplayTitle(_ display: PercentDisplay) -> String {
        switch display {
        case .remaining:
            text("percentDisplay.remaining")
        case .used:
            text("percentDisplay.used")
        case .both:
            text("percentDisplay.both")
        }
    }

    static func refreshIntervalTitle(_ interval: RefreshInterval) -> String {
        switch interval {
        case .thirtySeconds:
            text("refreshInterval.thirtySeconds")
        case .oneMinute:
            text("refreshInterval.oneMinute")
        case .fiveMinutes:
            text("refreshInterval.fiveMinutes")
        }
    }

    static func emptyStateMessage(_ emptyState: EmptyState) -> String {
        switch emptyState {
        case .claudeNotInstalled:
            text("empty.claudeNotInstalled")
        case .noUsageData:
            text("empty.noUsageData")
        case .helperUnavailable:
            text("empty.helperUnavailable")
        case .cachedOnly:
            text("empty.cachedOnly")
        case .available:
            text("empty.available")
        }
    }

    static func notificationTitle(for kind: UsageNotificationKind) -> String {
        switch kind {
        case let .threshold(window, _):
            format("notifications.threshold.title", notificationWindowTitle(window))
        case .staleData:
            text("notifications.stale.title")
        }
    }

    static func notificationBody(
        for decision: UsageNotificationDecision,
        settings: ClaudePulseSettings
    ) -> String {
        switch decision.kind {
        case let .threshold(window, _):
            format(
                "notifications.threshold.body",
                decision.remainingPercent ?? 0,
                notificationWindowTitle(window)
            )
        case .staleData:
            format("notifications.stale.body", decision.staleAfterMinutes ?? settings.staleAfterMinutes)
        }
    }

    private static func notificationWindowTitle(_ window: UsageWindowKind) -> String {
        switch window {
        case .fiveHour:
            text("window.fiveHour.notification")
        case .weekly:
            text("window.weekly.notification")
        }
    }

    private static func preferredBundle(in bundle: Bundle) -> Bundle? {
        guard let identifier = overrideLanguage.localizationIdentifier,
              let path = bundle.path(forResource: identifier, ofType: "lproj") else {
            return nil
        }

        return Bundle(path: path)
    }
}
