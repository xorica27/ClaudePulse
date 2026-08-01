import ClaudePulseCore
import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    private enum Keys {
        static let sentNotificationKeys = "sentNotificationKeys"
    }

    private let userDefaults: UserDefaults
    private let centerProvider: () -> UNUserNotificationCenter

    init(
        userDefaults: UserDefaults = .standard,
        centerProvider: @escaping () -> UNUserNotificationCenter = { .current() }
    ) {
        self.userDefaults = userDefaults
        self.centerProvider = centerProvider
    }

    func requestAuthorizationIfNeeded() {
        guard canUseNotifications else {
            return
        }
        let center = centerProvider()
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func process(data: UsageData?, settings: ClaudePulseSettings) {
        guard settings.notificationsEnabled, canUseNotifications else {
            return
        }

        requestAuthorizationIfNeeded()
        let center = centerProvider()
        var sentKeys = Set(userDefaults.stringArray(forKey: Keys.sentNotificationKeys) ?? [])
        let decisions = NotificationPlanner.decisions(for: data, settings: settings, sentKeys: sentKeys)

        for decision in decisions {
            let content = UNMutableNotificationContent()
            content.title = L10n.notificationTitle(for: decision.kind)
            content.body = L10n.notificationBody(for: decision, settings: settings)
            let request = UNNotificationRequest(
                identifier: "claudepulse-\(decision.deduplicationKey)",
                content: content,
                trigger: nil
            )
            center.add(request)
            sentKeys.insert(decision.deduplicationKey)
        }

        userDefaults.set(Array(sentKeys).sorted(), forKey: Keys.sentNotificationKeys)
    }

    private var canUseNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
