import Foundation

public enum UsageWindowKind: String, Codable, Equatable, Sendable {
    case fiveHour
    case weekly

    public var menuTitle: String {
        switch self {
        case .fiveHour:
            "5-hour"
        case .weekly:
            "weekly"
        }
    }
}

public enum UsageNotificationKind: Equatable, Sendable {
    case threshold(window: UsageWindowKind, threshold: Int)
    case staleData
}

public struct UsageNotificationDecision: Equatable, Sendable {
    public let kind: UsageNotificationKind
    public let title: String
    public let body: String
    public let remainingPercent: Int?
    public let staleAfterMinutes: Int?
    public let deduplicationKey: String

    public init(
        kind: UsageNotificationKind,
        title: String,
        body: String,
        deduplicationKey: String,
        remainingPercent: Int? = nil,
        staleAfterMinutes: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.remainingPercent = remainingPercent
        self.staleAfterMinutes = staleAfterMinutes
        self.deduplicationKey = deduplicationKey
    }
}

public enum NotificationPlanner {
    public static func decisions(
        for data: UsageData?,
        settings: ClaudePulseSettings,
        sentKeys: Set<String>,
        now: Date = Date()
    ) -> [UsageNotificationDecision] {
        guard settings.notificationsEnabled, let data else {
            return []
        }

        var decisions: [UsageNotificationDecision] = []
        decisions.append(contentsOf: thresholdDecisions(
            window: data.snapshot.primary,
            kind: .fiveHour,
            thresholds: settings.notifyFiveHourThresholds,
            sentKeys: sentKeys
        ))
        decisions.append(contentsOf: thresholdDecisions(
            window: data.snapshot.secondary,
            kind: .weekly,
            thresholds: settings.notifyWeeklyThresholds,
            sentKeys: sentKeys
        ))

        if DisplayFormatter.isStale(data, staleAfterMinutes: settings.staleAfterMinutes, now: now) {
            let key = "stale-\(Int(data.fetchedAt.timeIntervalSince1970))-\(settings.staleAfterMinutes)"
            if !sentKeys.contains(key) {
                decisions.append(UsageNotificationDecision(
                    kind: .staleData,
                    title: "ClaudePulse data is stale",
                    body: "ClaudePulse has not refreshed successfully for \(settings.staleAfterMinutes) minutes.",
                    deduplicationKey: key,
                    staleAfterMinutes: settings.staleAfterMinutes
                ))
            }
        }

        return decisions
    }

    private static func thresholdDecisions(
        window: UsageWindow?,
        kind: UsageWindowKind,
        thresholds: [Int],
        sentKeys: Set<String>
    ) -> [UsageNotificationDecision] {
        guard let window else {
            return []
        }

        let crossedThresholds = ClaudePulseSettings.defaults
            .normalizedThresholdsForPlanner(thresholds)
            .filter { window.remainingPercent <= $0 }

        let resetKey = window.resetsAt.map(String.init) ?? "unknown"

        return crossedThresholds.compactMap { threshold in
            let key = "threshold-\(kind.rawValue)-\(threshold)-\(resetKey)"
            guard !sentKeys.contains(key) else {
                return nil
            }

            return UsageNotificationDecision(
                kind: .threshold(window: kind, threshold: threshold),
                title: "Claude \(kind.menuTitle) limit is low",
                body: "\(window.remainingPercent)% remaining in the \(kind.menuTitle) window.",
                deduplicationKey: key,
                remainingPercent: window.remainingPercent
            )
        }
    }
}

private extension ClaudePulseSettings {
    func normalizedThresholdsForPlanner(_ thresholds: [Int]) -> [Int] {
        var normalized: [Int] = []
        for threshold in thresholds.sorted(by: >) where (1...100).contains(threshold) {
            if normalized.last != threshold {
                normalized.append(threshold)
            }
        }
        return normalized
    }
}
