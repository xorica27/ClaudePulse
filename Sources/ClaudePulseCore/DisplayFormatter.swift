import Foundation

/// The single formatter for everything ClaudePulse renders.
///
/// Localisation enters through `strings` and `locale`; there is deliberately no
/// second, localised copy of this logic. Callers with a bundle pass their own
/// `UsageFormatStrings`, everyone else gets `.english`.
public enum DisplayFormatter {
    public static func statusTitle(
        for data: UsageData?,
        mode: DisplayMode,
        percentDisplay: PercentDisplay = .remaining,
        staleAfterMinutes: Int = ClaudePulseSettings.defaults.staleAfterMinutes,
        now: Date = Date(),
        strings: UsageFormatStrings = .english,
        locale: Locale = .current
    ) -> String {
        guard let data else {
            return strings.unavailable
        }

        if data.snapshot.primary == nil && data.snapshot.secondary == nil {
            return strings.unavailable
        }

        if data.snapshot.isLimited {
            return strings.limited
        }

        let prefix: String
        if isStale(data, staleAfterMinutes: staleAfterMinutes, now: now) {
            prefix = "\(strings.stale) "
        } else if isLow(data) {
            prefix = "\(strings.low) "
        } else {
            prefix = ""
        }

        let fiveHour = percentText(data.snapshot.primary, display: percentDisplay, strings: strings, locale: locale)
        let weekly = percentText(data.snapshot.secondary, display: percentDisplay, strings: strings, locale: locale)

        switch mode {
        case .both:
            return "\(prefix)\(strings.fiveHourShort) \(fiveHour) \(strings.weeklyShort) \(weekly)"
        case .fiveHour:
            return "\(prefix)\(strings.fiveHourShort) \(fiveHour)"
        case .weekly:
            return "\(prefix)\(strings.weeklyShort) \(weekly)"
        }
    }

    public static func percentText(
        _ window: UsageWindow?,
        display: PercentDisplay = .remaining,
        strings: UsageFormatStrings = .english,
        locale: Locale = .current
    ) -> String {
        guard let window else {
            return strings.percentUnknown
        }

        switch display {
        case .remaining:
            return format(strings.percentRemaining, locale, window.remainingPercent)
        case .used:
            return format(strings.percentUsed, locale, window.usedPercent)
        case .both:
            return format(strings.percentRemainingAndUsed, locale, window.remainingPercent, window.usedPercent)
        }
    }

    public static func resetText(
        _ epochSeconds: Int?,
        display: ResetDisplay = .absolute,
        now: Date = Date(),
        strings: UsageFormatStrings = .english,
        locale: Locale = .current
    ) -> String {
        guard let epochSeconds else {
            return strings.resetUnknown
        }

        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        switch display {
        case .absolute:
            return absoluteResetText(date, now: now, strings: strings, locale: locale)
        case .relative:
            return relativeUntil(date, now: now, strings: strings, locale: locale)
        case .both:
            return format(
                strings.resetAbsoluteAndRelative,
                locale,
                absoluteResetText(date, now: now, strings: strings, locale: locale),
                relativeUntil(date, now: now, strings: strings, locale: locale)
            )
        }
    }

    /// "in 2h 15m". A window whose reset has already passed reads "now" rather
    /// than counting up from zero.
    public static func relativeUntil(
        _ date: Date,
        now: Date = Date(),
        strings: UsageFormatStrings = .english,
        locale: Locale = .current
    ) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else {
            return strings.relativeNow
        }

        let (days, hours, minutes) = split(seconds)
        if days > 0 {
            return format(strings.relativeDayHourUntil, locale, days, hours)
        }
        if hours > 0 {
            return format(strings.relativeHourMinuteUntil, locale, hours, minutes)
        }
        return format(strings.relativeMinuteUntil, locale, minutes)
    }

    public static func relativeAge(
        _ date: Date,
        now: Date = Date(),
        strings: UsageFormatStrings = .english,
        locale: Locale = .current
    ) -> String {
        let (days, hours, minutes) = split(max(0, Int(now.timeIntervalSince(date))))
        if days > 0 {
            return format(strings.relativeDayHourAgo, locale, days, hours)
        }
        if hours > 0 {
            return format(strings.relativeHourMinuteAgo, locale, hours, minutes)
        }
        return format(strings.relativeMinuteAgo, locale, minutes)
    }

    public static func detailLine(
        label: String,
        window: UsageWindow?,
        resetDisplay: ResetDisplay = .absolute,
        now: Date = Date(),
        strings: UsageFormatStrings = .english,
        locale: Locale = .current
    ) -> String {
        guard let window else {
            return format(strings.detailWindowUnavailable, locale, label)
        }

        return format(
            strings.detailWindow,
            locale,
            label,
            window.remainingPercent,
            resetText(window.resetsAt, display: resetDisplay, now: now, strings: strings, locale: locale),
            window.usedPercent
        )
    }

    public static func isStale(_ data: UsageData, staleAfterMinutes: Int, now: Date = Date()) -> Bool {
        if data.source == .cache {
            return true
        }
        let staleAfter = TimeInterval(max(1, staleAfterMinutes) * 60)
        return now.timeIntervalSince(data.fetchedAt) >= staleAfter
    }

    public static func isLow(_ data: UsageData, threshold: Int = 10) -> Bool {
        [data.snapshot.primary, data.snapshot.secondary].contains { window in
            guard let window else {
                return false
            }
            return window.remainingPercent <= threshold
        }
    }

    private static func absoluteResetText(
        _ date: Date,
        now: Date,
        strings: UsageFormatStrings,
        locale: Locale
    ) -> String {
        var calendar = Calendar.current
        calendar.locale = locale

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, inSameDayAs: now) ? strings.resetTimeTemplate : strings.resetDateTemplate
        )
        return formatter.string(from: date)
    }

    private static func split(_ seconds: Int) -> (days: Int, hours: Int, minutes: Int) {
        (seconds / 86_400, (seconds % 86_400) / 3_600, (seconds % 3_600) / 60)
    }

    private static func format(_ pattern: String, _ locale: Locale, _ arguments: any CVarArg...) -> String {
        String(format: pattern, locale: locale, arguments: arguments)
    }
}
