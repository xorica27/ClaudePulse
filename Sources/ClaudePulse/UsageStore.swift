import ClaudePulseCore
import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    private enum Keys {
        static let cachedData = "cachedUsageData"
    }

    private let usageClient: ClaudeUsageClient
    private let userDefaults: UserDefaults
    private var isRefreshing = false

    @Published var data: UsageData? {
        didSet {
            onChange?()
        }
    }

    @Published var lastErrorMessage: String?

    @Published var emptyState: EmptyState = .noUsageData

    var onChange: (() -> Void)?

    var claudeAppVersion: String? {
        usageClient.claudeAppVersion
    }

    init(userDefaults: UserDefaults = .standard, usageClient: ClaudeUsageClient = ClaudeUsageClient()) {
        self.userDefaults = userDefaults
        self.usageClient = usageClient
        self.data = Self.loadCachedData(from: userDefaults)
        self.emptyState = EmptyStateClassifier.classify(data: data, lastError: nil)
    }

    func refresh() {
        if isRefreshing {
            return
        }
        isRefreshing = true
        let cachedData = data

        Task.detached(priority: .utility) { [usageClient, cachedData] in
            let result: UsageData
            let lastErrorMessage: String?
            let emptyState: EmptyState
            do {
                result = try usageClient.fetch()
                lastErrorMessage = nil
                emptyState = EmptyStateClassifier.classify(data: result, lastError: nil)
            } catch {
                if let cached = cachedData {
                    result = cached.replacingSource(.cache, errorMessage: error.localizedDescription)
                } else {
                    let empty = UsageSnapshot(planType: nil, primary: nil, secondary: nil, usageReachedType: nil)
                    result = UsageData(
                        snapshot: empty,
                        additionalLimits: [:],
                        source: .cache,
                        fetchedAt: Date(),
                        errorMessage: error.localizedDescription
                    )
                }
                lastErrorMessage = error.localizedDescription
                emptyState = EmptyStateClassifier.classify(data: result, lastError: error)
            }

            await MainActor.run {
                self.lastErrorMessage = lastErrorMessage
                self.emptyState = emptyState
                self.data = result
                if result.source != .cache {
                    Self.save(result, to: self.userDefaults)
                }
                self.isRefreshing = false
            }
        }
    }

    private static func loadCachedData(from userDefaults: UserDefaults) -> UsageData? {
        guard let data = userDefaults.data(forKey: Keys.cachedData) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageData.self, from: data)
    }

    private static func save(_ value: UsageData, to userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        userDefaults.set(data, forKey: Keys.cachedData)
    }
}
