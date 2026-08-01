import Foundation
import Testing
@testable import ClaudePulseCore

struct ClaudePulseTests {
    @Test
    func testLocalizationResourcesExistForSupportedLocales() throws {
        let resources = packageRoot()
            .appendingPathComponent("Sources/ClaudePulse/Resources", isDirectory: true)
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let requiredKeys = [
            "app.name",
            "status.unavailable",
            "status.limited",
            "status.stale",
            "status.low",
            "status.fiveHour.short",
            "status.weekly.short",
            "percent.used",
            "percent.remainingAndUsed",
            "menu.refreshNow",
            "menu.openClaudeUsage",
            "menu.preferences",
            "menu.launchAtLogin",
            "menu.checkForUpdates",
            "menu.about",
            "menu.quit",
            "preferences.title",
            "preferences.tab.display",
            "preferences.tab.alerts",
            "preferences.tab.diagnostics",
            "preferences.tab.about",
            "preferences.language",
            "preferences.sourcePath",
            "preferences.claudeVersion",
            "preferences.checkForUpdates",
            "appLanguage.system",
            "appLanguage.english",
            "appLanguage.simplifiedChinese",
            "appLanguage.traditionalChinese",
            "about.privacyNote",
            "notifications.threshold.title",
            "notifications.threshold.body",
            "notifications.stale.title",
            "notifications.stale.body",
            "empty.claudeNotInstalled",
            "empty.noUsageData",
            "empty.helperUnavailable",
            "empty.cachedOnly",
            "empty.available"
        ]

        for locale in locales {
            let localeDirectory = resources.appendingPathComponent("\(locale).lproj", isDirectory: true)
            let strings = try loadStrings(localeDirectory.appendingPathComponent("Localizable.strings"))
            let infoPlist = try loadStrings(localeDirectory.appendingPathComponent("InfoPlist.strings"))

            for key in requiredKeys {
                #expect(strings[key]?.isEmpty == false, "Missing \(key) in \(locale)")
            }
            #expect(infoPlist["CFBundleDisplayName"]?.isEmpty == false, "Missing display name in \(locale)")
        }
    }

    @Test
    func testEnglishLocalizationKeepsCurrentStatusVocabulary() throws {
        let resources = packageRoot()
            .appendingPathComponent("Sources/ClaudePulse/Resources/en.lproj/Localizable.strings")
        let strings = try loadStrings(resources)

        #expect(strings["status.limited"] == "limited")
        #expect(strings["status.stale"] == "stale")
        #expect(strings["status.low"] == "low")
        #expect(strings["percent.used"] == "%d%% used")
        #expect(strings["percent.remainingAndUsed"] == "%d%% rem/%d%% used")
    }

    @Test
    func testDmgPackagingIsDocumentedAndScripted() throws {
        let root = packageRoot()
        let packageDmgScript = root.appendingPathComponent("scripts/package-dmg.sh")
        let backgroundScript = root.appendingPathComponent("scripts/generate-dmg-background.swift")
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: packageDmgScript.path))
        #expect(FileManager.default.fileExists(atPath: backgroundScript.path))
        #expect(readme.contains("ClaudePulse-macos-arm64.dmg"))
    }

    @Test
    func testLaunchAtLoginDoesNotBootstrapImmediately() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/ClaudePulse/LaunchAtLoginManager.swift"),
            encoding: .utf8
        )

        #expect(source.contains("\"RunAtLoad\": true"))
        #expect(!source.contains("\"bootstrap\""))
    }

    @Test
    func testRemainingPercentClampsFromUsedPercent() {
        #expect(UsageWindow(usedPercent: 9, windowDurationMins: 300, resetsAt: nil).remainingPercent == 91)
        #expect(UsageWindow(usedPercent: -10, windowDurationMins: 300, resetsAt: nil).remainingPercent == 100)
        #expect(UsageWindow(usedPercent: 120, windowDurationMins: 300, resetsAt: nil).remainingPercent == 0)
    }

    @Test
    func testDisplayModes() {
        let data = sampleData()

        #expect(DisplayFormatter.statusTitle(for: data, mode: .both) == "5h 91% W 90%")
        #expect(DisplayFormatter.statusTitle(for: data, mode: .fiveHour) == "5h 91%")
        #expect(DisplayFormatter.statusTitle(for: data, mode: .weekly) == "W 90%")
        #expect(DisplayFormatter.statusTitle(for: nil, mode: .both) == "Usage unavailable")
    }

    @Test
    func testPercentDisplayModes() {
        let data = sampleData()

        #expect(DisplayFormatter.statusTitle(for: data, mode: .both, percentDisplay: .remaining) == "5h 91% W 90%")
        #expect(DisplayFormatter.statusTitle(for: data, mode: .both, percentDisplay: .used) == "5h 9% used W 10% used")
        #expect(DisplayFormatter.statusTitle(for: data, mode: .both, percentDisplay: .both) == "5h 91% rem/9% used W 90% rem/10% used")
    }

    @Test
    func testStatusMarkersUseExpectedPrecedence() {
        let now = Date(timeIntervalSince1970: 2_000)
        let staleData = sampleData(source: .cache, fetchedAt: Date(timeIntervalSince1970: 1_000))
        let lowData = sampleData(
            primary: UsageWindow(usedPercent: 95, windowDurationMins: 300, resetsAt: nil),
            secondary: UsageWindow(usedPercent: 10, windowDurationMins: 10080, resetsAt: nil)
        )
        let limitedData = sampleData(usageReachedType: "primary")

        #expect(DisplayFormatter.statusTitle(for: lowData, mode: .both, percentDisplay: .remaining, staleAfterMinutes: 30, now: now) == "low 5h 5% W 90%")
        #expect(DisplayFormatter.statusTitle(for: staleData, mode: .both, percentDisplay: .remaining, staleAfterMinutes: 30, now: now) == "stale 5h 91% W 90%")
        #expect(DisplayFormatter.statusTitle(for: limitedData, mode: .both, percentDisplay: .remaining, staleAfterMinutes: 30, now: now) == "limited")
    }

    @Test
    func testSettingsPersistenceDefaultsAndRoundTrip() throws {
        let suiteName = "ClaudePulseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ClaudePulseSettings.load(from: defaults) == .defaults)
        #expect(ClaudePulseSettings.defaults.appLanguage == .system)

        let settings = ClaudePulseSettings(
            displayMode: .weekly,
            percentDisplay: .both,
            refreshInterval: .fiveMinutes,
            appLanguage: .traditionalChinese,
            notificationsEnabled: true,
            notifyFiveHourThresholds: [10, 5],
            notifyWeeklyThresholds: [20],
            staleAfterMinutes: 45
        )
        settings.save(to: defaults)

        #expect(ClaudePulseSettings.load(from: defaults) == settings)
    }

    @Test
    func testSettingsMigrateLegacyDisplayMode() throws {
        let suiteName = "ClaudePulseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(DisplayMode.weekly.rawValue, forKey: "displayMode")

        #expect(ClaudePulseSettings.load(from: defaults).displayMode == .weekly)
    }

    @Test
    func testNotificationDecisionsCrossThresholdOncePerResetWindow() {
        let settings = ClaudePulseSettings.defaults.withNotificationsEnabled()
        let data = sampleData(
            primary: UsageWindow(usedPercent: 91, windowDurationMins: 300, resetsAt: 3_000),
            secondary: UsageWindow(usedPercent: 10, windowDurationMins: 10080, resetsAt: 4_000)
        )
        var sent: Set<String> = []

        let first = NotificationPlanner.decisions(for: data, settings: settings, sentKeys: sent, now: Date(timeIntervalSince1970: 2_000))
        #expect(first.map(\.kind) == [
            .threshold(window: .fiveHour, threshold: 20),
            .threshold(window: .fiveHour, threshold: 10)
        ])
        sent.formUnion(first.map(\.deduplicationKey))

        let repeated = NotificationPlanner.decisions(for: data, settings: settings, sentKeys: sent, now: Date(timeIntervalSince1970: 2_100))
        #expect(repeated.isEmpty)
    }

    @Test
    func testNotificationThresholdsNormalizeDuplicatesAndInvalidValues() {
        let settings = ClaudePulseSettings(
            displayMode: .both,
            percentDisplay: .remaining,
            refreshInterval: .oneMinute,
            notificationsEnabled: true,
            notifyFiveHourThresholds: [10, 20, 20, 200, 0, 5],
            notifyWeeklyThresholds: [],
            staleAfterMinutes: 30
        )
        let data = sampleData(
            primary: UsageWindow(usedPercent: 91, windowDurationMins: 300, resetsAt: 3_000),
            secondary: UsageWindow(usedPercent: 10, windowDurationMins: 10080, resetsAt: 4_000)
        )

        let decisions = NotificationPlanner.decisions(for: data, settings: settings, sentKeys: [], now: Date(timeIntervalSince1970: 2_000))

        #expect(decisions.map(\.kind) == [
            .threshold(window: .fiveHour, threshold: 20),
            .threshold(window: .fiveHour, threshold: 10)
        ])
    }

    @Test
    func testNotificationDecisionsIncludeStaleDataWhenEnabled() {
        let settings = ClaudePulseSettings.defaults.withNotificationsEnabled()
        let data = sampleData(source: .cache, fetchedAt: Date(timeIntervalSince1970: 0))

        let decisions = NotificationPlanner.decisions(for: data, settings: settings, sentKeys: [], now: Date(timeIntervalSince1970: 1_900))

        #expect(decisions.map(\.kind) == [.staleData])
    }

    @Test
    func testEmptyStateClassification() {
        #expect(EmptyStateClassifier.classify(data: nil, lastError: ClaudeUsageError.claudeAppMissing("/Applications/Claude.app")) == .claudeNotInstalled)

        let empty = UsageData(
            snapshot: UsageSnapshot(planType: nil, primary: nil, secondary: nil, usageReachedType: nil),
            additionalLimits: [:],
            source: .cache,
            fetchedAt: Date(),
            errorMessage: ClaudeUsageError.malformedResponse.localizedDescription
        )
        #expect(EmptyStateClassifier.classify(data: empty, lastError: ClaudeUsageError.malformedResponse) == .noUsageData)

        let cached = sampleData(source: .cache)
        #expect(EmptyStateClassifier.classify(data: cached, lastError: ClaudeUsageError.noExactUsageData(scannedPaths: [])) == .cachedOnly)
    }

    @Test
    func testResetTextUsesTimeForSameDayAndDateForFutureDay() {
        let now = Date(timeIntervalSince1970: 1_778_719_500)
        let sameDay = 1_778_736_433
        let futureDay = 1_779_152_172

        #expect(DisplayFormatter.resetText(sameDay, now: now) == "13:27")
        #expect(DisplayFormatter.resetText(futureDay, now: now) == "19 May")
    }

    @Test
    func testParsesLocalClaudeUsagePayload() throws {
        let json = """
        {
          "usage": {
            "primary": {"usedPercent": 9, "windowDurationMins": 300, "resetsAt": 1778736433},
            "secondary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1779152172},
            "planType": "prolite",
            "extraUsage": {
              "primary": {"used": 5, "limit": 20, "reset_at": 1778738702000}
            }
          }
        }
        """
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let data = try ClaudeUsagePayloadParser.parse(result: object, source: .localStorage, sourcePath: "/tmp/Local Storage/leveldb/000001.log")

        #expect(data.snapshot.planType == "prolite")
        #expect(data.snapshot.primary?.remainingPercent == 91)
        #expect(data.snapshot.secondary?.remainingPercent == 90)
        #expect(data.source == .localStorage)
        #expect(data.sourcePath == "/tmp/Local Storage/leveldb/000001.log")
        #expect(data.additionalLimits["extraUsage"]?.primary?.usedPercent == 25)
    }

    @Test
    func testParsesClaudeAPIUsagePayload() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 100.0,
            "resets_at": "2026-06-22T06:39:59.849810+00:00"
          },
          "seven_day": {
            "utilization": 9.0,
            "resets_at": "2026-06-28T21:59:59.849831+00:00"
          },
          "seven_day_opus": null,
          "seven_day_sonnet": {
            "utilization": 12.4,
            "resets_at": "2026-06-28T21:59:59.849831+00:00"
          },
          "extra_usage": {
            "is_enabled": false,
            "monthly_limit": null,
            "used_credits": null,
            "utilization": null
          }
        }
        """
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let data = try ClaudeUsagePayloadParser.parse(result: object, source: .claudeAPI, sourcePath: "https://claude.ai/api/organizations/example/usage")

        #expect(data.source == .claudeAPI)
        #expect(data.snapshot.primary?.usedPercent == 100)
        #expect(data.snapshot.primary?.remainingPercent == 0)
        #expect(data.snapshot.primary?.resetsAt != nil)
        #expect(data.snapshot.secondary?.usedPercent == 9)
        #expect(data.snapshot.secondary?.remainingPercent == 91)
        #expect(data.additionalLimits["seven_day_sonnet"]?.secondary?.usedPercent == 12)
    }

    @Test
    func testClientFindsLocalStoragePayloadFromFixtureDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudePulseTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appPath = root.appendingPathComponent("Claude.app", isDirectory: true)
        let appContents = appPath.appendingPathComponent("Contents", isDirectory: true)
        let supportPath = root.appendingPathComponent("Application Support/Claude", isDirectory: true)
        let localStorage = supportPath.appendingPathComponent("Local Storage/leveldb", isDirectory: true)
        let logsPath = root.appendingPathComponent("Logs/Claude", isDirectory: true)

        try FileManager.default.createDirectory(at: appContents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localStorage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsPath, withIntermediateDirectories: true)

        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3"]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: appContents.appendingPathComponent("Info.plist"))

        let payload = """
        leveldb-prefix {"usage":{"plan_type":"max","five_hour":{"used":12,"limit":40,"reset_at":1778736433000},"weekly":{"used_percent":"10%","window_minutes":10080}}} leveldb-suffix
        """
        try Data(payload.utf8).write(to: localStorage.appendingPathComponent("000001.log"))

        let client = ClaudeUsageClient(
            appPath: appPath.path,
            supportPath: supportPath.path,
            logsPath: logsPath.path,
            maxFileBytes: 100_000,
            maxFilesPerLocation: 10
        )
        let data = try client.fetch()

        #expect(client.claudeAppVersion == "1.2.3")
        #expect(data.source == .localStorage)
        #expect(data.sourcePath?.hasSuffix("000001.log") == true)
        #expect(data.snapshot.planType == "max")
        #expect(data.snapshot.primary?.usedPercent == 30)
        #expect(data.snapshot.primary?.resetsAt == 1_778_736_433)
        #expect(data.snapshot.secondary?.remainingPercent == 90)
    }

    @Test
    func testLiveClaudeUsageClientWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["CLAUDEPULSE_LIVE_USAGE_TEST"] == "1" else {
            return
        }

        let data = try ClaudeUsageClient().fetch()

        #expect(data.source == .claudeAPI)
        #expect(data.snapshot.primary != nil || data.snapshot.secondary != nil)
        #expect(data.sourcePath == "https://claude.ai/api/organizations/<organization>/usage")
    }

    private func sampleData(
        primary: UsageWindow = UsageWindow(usedPercent: 9, windowDurationMins: 300, resetsAt: nil),
        secondary: UsageWindow = UsageWindow(usedPercent: 10, windowDurationMins: 10080, resetsAt: nil),
        source: UsageSource = .localStorage,
        fetchedAt: Date = Date(),
        usageReachedType: String? = nil
    ) -> UsageData {
        UsageData(
            snapshot: UsageSnapshot(
                planType: "prolite",
                primary: primary,
                secondary: secondary,
                usageReachedType: usageReachedType
            ),
            additionalLimits: [:],
            source: source,
            fetchedAt: fetchedAt
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadStrings(_ url: URL) throws -> [String: String] {
        let dictionary = try #require(NSDictionary(contentsOf: url) as? [String: String])
        return dictionary
    }
}

private extension ClaudePulseSettings {
    func withNotificationsEnabled() -> ClaudePulseSettings {
        ClaudePulseSettings(
            displayMode: displayMode,
            percentDisplay: percentDisplay,
            refreshInterval: refreshInterval,
            appLanguage: appLanguage,
            notificationsEnabled: true,
            notifyFiveHourThresholds: notifyFiveHourThresholds,
            notifyWeeklyThresholds: notifyWeeklyThresholds,
            staleAfterMinutes: staleAfterMinutes
        )
    }
}
