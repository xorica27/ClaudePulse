import ClaudePulseCore
import Foundation

@MainActor
enum LocalizedDisplayFormatter {
    static func statusTitle(
        for data: UsageData?,
        mode: DisplayMode,
        percentDisplay: PercentDisplay,
        staleAfterMinutes: Int,
        now: Date = Date()
    ) -> String {
        guard let data else {
            return L10n.text("status.unavailable")
        }

        if data.snapshot.primary == nil && data.snapshot.secondary == nil {
            return L10n.text("status.unavailable")
        }

        if data.snapshot.isLimited {
            return L10n.text("status.limited")
        }

        let prefix: String
        if DisplayFormatter.isStale(data, staleAfterMinutes: staleAfterMinutes, now: now) {
            prefix = "\(L10n.text("status.stale")) "
        } else if DisplayFormatter.isLow(data) {
            prefix = "\(L10n.text("status.low")) "
        } else {
            prefix = ""
        }

        let fiveHour = percentText(data.snapshot.primary, display: percentDisplay)
        let weekly = percentText(data.snapshot.secondary, display: percentDisplay)

        switch mode {
        case .both:
            return "\(prefix)\(L10n.text("status.fiveHour.short")) \(fiveHour) \(L10n.text("status.weekly.short")) \(weekly)"
        case .fiveHour:
            return "\(prefix)\(L10n.text("status.fiveHour.short")) \(fiveHour)"
        case .weekly:
            return "\(prefix)\(L10n.text("status.weekly.short")) \(weekly)"
        }
    }

    static func percentText(_ window: UsageWindow?, display: PercentDisplay) -> String {
        guard let window else {
            return L10n.text("percent.unknown")
        }

        switch display {
        case .remaining:
            return L10n.format("percent.remaining", window.remainingPercent)
        case .used:
            return L10n.format("percent.used", window.usedPercent)
        case .both:
            return L10n.format("percent.remainingAndUsed", window.remainingPercent, window.usedPercent)
        }
    }

    static func resetText(_ epochSeconds: Int?, now: Date = Date()) -> String {
        guard let epochSeconds else {
            return L10n.text("reset.unknown")
        }

        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current

        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
        }

        return formatter.string(from: date)
    }

    static func detailLine(label: String, window: UsageWindow?) -> String {
        guard let window else {
            return L10n.format("detail.window.unavailable", label)
        }

        return L10n.format(
            "detail.window",
            label,
            window.remainingPercent,
            resetText(window.resetsAt),
            window.usedPercent
        )
    }

    static func relativeAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return L10n.format("relative.dayHourAgo", days, hours)
        }
        if hours > 0 {
            return L10n.format("relative.hourMinuteAgo", hours, minutes)
        }
        return L10n.format("relative.minuteAgo", minutes)
    }
}
