import Foundation

public enum DisplayFormatter {
    public static func statusTitle(for data: UsageData?, mode: DisplayMode) -> String {
        statusTitle(for: data, mode: mode, percentDisplay: .remaining)
    }

    public static func statusTitle(
        for data: UsageData?,
        mode: DisplayMode,
        percentDisplay: PercentDisplay,
        staleAfterMinutes: Int = ClaudePulseSettings.defaults.staleAfterMinutes,
        now: Date = Date()
    ) -> String {
        guard let data else {
            return "Usage unavailable"
        }

        if data.snapshot.primary == nil && data.snapshot.secondary == nil {
            return "Usage unavailable"
        }

        if data.snapshot.isLimited {
            return "limited"
        }

        let prefix: String
        if isStale(data, staleAfterMinutes: staleAfterMinutes, now: now) {
            prefix = "stale "
        } else if isLow(data) {
            prefix = "low "
        } else {
            prefix = ""
        }

        let fiveHour = percentText(data.snapshot.primary, display: percentDisplay)
        let weekly = percentText(data.snapshot.secondary, display: percentDisplay)

        switch mode {
        case .both:
            return "\(prefix)5h \(fiveHour) W \(weekly)"
        case .fiveHour:
            return "\(prefix)5h \(fiveHour)"
        case .weekly:
            return "\(prefix)W \(weekly)"
        }
    }

    public static func percentText(_ window: UsageWindow?) -> String {
        percentText(window, display: .remaining)
    }

    public static func percentText(_ window: UsageWindow?, display: PercentDisplay) -> String {
        guard let window else {
            return "?%"
        }

        switch display {
        case .remaining:
            return "\(window.remainingPercent)%"
        case .used:
            return "\(window.usedPercent)% used"
        case .both:
            return "\(window.remainingPercent)% rem/\(window.usedPercent)% used"
        }
    }

    public static func resetText(
        _ epochSeconds: Int?,
        display: ResetDisplay = .absolute,
        now: Date = Date()
    ) -> String {
        guard let epochSeconds else {
            return "unknown"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        switch display {
        case .absolute:
            return absoluteResetText(date, now: now)
        case .relative:
            return relativeUntil(date, now: now)
        case .both:
            return "\(absoluteResetText(date, now: now)) (\(relativeUntil(date, now: now)))"
        }
    }

    private static func absoluteResetText(_ date: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "d MMM"
        return formatter.string(from: date)
    }

    /// "in 2h 15m". A window whose reset has already passed reads "now" rather
    /// than counting up from zero.
    public static func relativeUntil(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else {
            return "now"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "in \(days)d \(hours)h"
        }
        if hours > 0 {
            return "in \(hours)h \(minutes)m"
        }
        return "in \(minutes)m"
    }

    public static func detailLine(
        label: String,
        window: UsageWindow?,
        resetDisplay: ResetDisplay = .absolute,
        now: Date = Date()
    ) -> String {
        guard let window else {
            return "\(label): unavailable"
        }
        let reset = resetText(window.resetsAt, display: resetDisplay, now: now)
        return "\(label): \(window.remainingPercent)% remaining, resets \(reset) (\(window.usedPercent)% used)"
    }

    public static func relativeAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h ago"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        }
        return "\(minutes)m ago"
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
}
