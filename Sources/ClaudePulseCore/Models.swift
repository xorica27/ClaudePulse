import Foundation

public enum DisplayMode: String, CaseIterable, Codable, Sendable {
    case both
    case fiveHour
    case weekly

    public var menuTitle: String {
        switch self {
        case .both:
            "Both windows"
        case .fiveHour:
            "5h window"
        case .weekly:
            "Weekly window"
        }
    }
}

public enum UsageSource: String, Codable, Sendable {
    case claudeAPI = "claude-api"
    case localStorage = "local-storage"
    case indexedDB = "indexed-db"
    case sessionStorage = "session-storage"
    case log = "log"
    case cache = "cache"
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Int?

    public init(usedPercent: Int, windowDurationMins: Int?, resetsAt: Int?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let planType: String?
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let usageReachedType: String?

    public init(planType: String?, primary: UsageWindow?, secondary: UsageWindow?, usageReachedType: String?) {
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.usageReachedType = usageReachedType
    }

    public var isLimited: Bool {
        usageReachedType != nil
    }

    public func withPlanType(_ planType: String?) -> UsageSnapshot {
        UsageSnapshot(
            planType: planType,
            primary: primary,
            secondary: secondary,
            usageReachedType: usageReachedType
        )
    }
}

/// A model- or feature-specific limit reported alongside the main windows, such as
/// the separate weekly Fable, Opus, and Sonnet buckets.
public struct NamedUsageLimit: Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: UsageWindowKind
    public let window: UsageWindow

    public init(key: String, label: String, kind: UsageWindowKind, window: UsageWindow) {
        self.key = key
        self.label = label
        self.kind = kind
        self.window = window
    }
}

public enum UsageLimitLabel {
    private static let knownNames: [String: String] = [
        "opus": "Opus",
        "sonnet": "Sonnet",
        "fable": "Fable",
        "haiku": "Haiku",
        "oauth_apps": "OAuth apps",
        "cowork": "Cowork",
        "extra": "Extra usage",
        "extra_usage": "Extra usage",
        "extrausage": "Extra usage",
        "overage": "Overage",
        "additional": "Additional usage",
        "additional_usage": "Additional usage"
    ]

    public static func label(forKey key: String) -> String {
        var name = key.lowercased()
        for prefix in ["seven_day_", "sevenday_", "five_hour_", "fivehour_", "weekly_", "daily_"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }

        if let known = knownNames[name] {
            return known
        }

        let words = name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? key : words.joined(separator: " ")
    }
}

public struct UsageData: Codable, Equatable, Sendable {
    public let snapshot: UsageSnapshot
    public let additionalLimits: [String: UsageSnapshot]
    public let source: UsageSource
    public let sourcePath: String?
    public let fetchedAt: Date
    public let errorMessage: String?

    public init(
        snapshot: UsageSnapshot,
        additionalLimits: [String: UsageSnapshot],
        source: UsageSource,
        sourcePath: String? = nil,
        fetchedAt: Date,
        errorMessage: String? = nil
    ) {
        self.snapshot = snapshot
        self.additionalLimits = additionalLimits
        self.source = source
        self.sourcePath = sourcePath
        self.fetchedAt = fetchedAt
        self.errorMessage = errorMessage
    }

    /// The model- and feature-specific limits, in a stable order fit for display.
    ///
    /// Only resetting windows qualify. The usage payload also carries credit pools
    /// (`spend`, `extra_usage`) that expose a percentage but never reset, and
    /// rendering those as a 5-hour or weekly window would misdescribe them.
    public var additionalLimitsForDisplay: [NamedUsageLimit] {
        additionalLimits
            .compactMap { key, snapshot -> NamedUsageLimit? in
                let kind: UsageWindowKind
                let window: UsageWindow
                if let secondary = snapshot.secondary {
                    kind = .weekly
                    window = secondary
                } else if let primary = snapshot.primary {
                    kind = .fiveHour
                    window = primary
                } else {
                    return nil
                }

                guard window.resetsAt != nil else {
                    return nil
                }

                return NamedUsageLimit(
                    key: key,
                    label: UsageLimitLabel.label(forKey: key),
                    kind: kind,
                    window: window
                )
            }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind == .fiveHour
                }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }

    public func withPlanType(_ planType: String?) -> UsageData {
        UsageData(
            snapshot: snapshot.withPlanType(planType),
            additionalLimits: additionalLimits,
            source: source,
            sourcePath: sourcePath,
            fetchedAt: fetchedAt,
            errorMessage: errorMessage
        )
    }

    public func replacingSource(_ source: UsageSource, errorMessage: String? = nil) -> UsageData {
        UsageData(
            snapshot: snapshot,
            additionalLimits: additionalLimits,
            source: source,
            sourcePath: sourcePath,
            fetchedAt: fetchedAt,
            errorMessage: errorMessage
        )
    }
}
