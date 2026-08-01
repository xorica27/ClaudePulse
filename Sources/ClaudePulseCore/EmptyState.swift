import Foundation

public enum EmptyState: Equatable, Sendable {
    case claudeNotInstalled
    case noUsageData
    case helperUnavailable
    case cachedOnly
    case available

    public var menuMessage: String {
        switch self {
        case .claudeNotInstalled:
            "Claude app was not found in /Applications."
        case .noUsageData:
            "No exact Claude usage payload was found in local app data."
        case .helperUnavailable:
            "Claude local usage data is unavailable right now."
        case .cachedOnly:
            "Showing cached usage data."
        case .available:
            "Claude usage is available."
        }
    }
}

public enum EmptyStateClassifier {
    public static func classify(data: UsageData?, lastError: Error?) -> EmptyState {
        if let clientError = lastError as? ClaudeUsageError,
           case .claudeAppMissing = clientError {
            return .claudeNotInstalled
        }

        guard let data else {
            return lastError == nil ? .noUsageData : .helperUnavailable
        }

        let hasWindow = data.snapshot.primary != nil || data.snapshot.secondary != nil
        if data.source == .cache && hasWindow {
            return .cachedOnly
        }

        if !hasWindow {
            return .noUsageData
        }

        return .available
    }
}
