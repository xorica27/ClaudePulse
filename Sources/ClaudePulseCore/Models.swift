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
