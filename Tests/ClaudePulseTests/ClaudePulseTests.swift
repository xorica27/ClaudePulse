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
            "percent.unknown",
            "percent.remaining",
            "percent.used",
            "percent.remainingAndUsed",
            "reset.unknown",
            "detail.window",
            "detail.window.unavailable",
            "relative.dayHourAgo",
            "relative.hourMinuteAgo",
            "relative.minuteAgo",
            "limit.labelWithWindow",
            "relative.dayHourUntil",
            "relative.hourMinuteUntil",
            "relative.minuteUntil",
            "relative.now",
            "reset.absoluteAndRelative",
            "preferences.reset",
            "resetDisplay.absolute",
            "resetDisplay.relative",
            "resetDisplay.both",
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
        #expect(readme.contains("ClaudePulse-macos-universal.dmg"))
    }

    /// `swift file.swift a b c` interprets the file, and swift-frontend leaves
    /// its whole invocation in CommandLine.arguments with the script's own
    /// arguments after a trailing `--`. Indexing arguments[1] therefore reads a
    /// compiler flag instead of the output path, which failed the usage guard
    /// and broke `package-dmg.sh` outright.
    @Test
    func testDmgBackgroundReadsArgumentsAfterTheFrontendSeparator() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("scripts/generate-dmg-background.swift"),
            encoding: .utf8
        )

        #expect(source.contains("lastIndex(of: \"--\")"))
        #expect(!source.contains("CommandLine.arguments[1]"))
        #expect(!source.contains("CommandLine.arguments.count == 2"))
    }

    /// The app has no architecture-specific code, so Intel support is purely a
    /// question of what the release script builds. Pin it: a build that quietly
    /// drops back to one slice would ship a download Intel Macs cannot open.
    @Test
    func testReleaseBuildIsUniversal() throws {
        let root = packageRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-release.sh"),
            encoding: .utf8
        )
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        #expect(buildScript.contains("CLAUDEPULSE_ARCHS:-arm64 x86_64"))
        #expect(buildScript.contains("lipo -create"))
        #expect(buildScript.contains("lipo -archs"))
        #expect(readme.contains("Apple Silicon or Intel Mac"))

        // Several --arch flags on one `swift build` need xcbuild, which ships
        // only with full Xcode. The slices are built separately and merged so
        // the Command Line Tools are enough.
        #expect(!buildScript.contains("ARCH_FLAGS"))
    }

    /// Artifact names are derived from the built binary rather than hardcoded,
    /// so a filename can never claim a slice the app does not carry.
    @Test
    func testPackagingScriptsNameArtifactsFromTheBinary() throws {
        let root = packageRoot()
        let slugHelper = root.appendingPathComponent("scripts/artifact-slug.sh")

        #expect(FileManager.default.fileExists(atPath: slugHelper.path))

        for script in ["scripts/package-dmg.sh", "scripts/package-zip.sh"] {
            let source = try String(
                contentsOf: root.appendingPathComponent(script),
                encoding: .utf8
            )

            #expect(source.contains("artifact-slug.sh"))
            #expect(source.contains("binary_arch_slug"))
            #expect(!source.contains("macos-arm64"))
        }
    }

    @Test
    func testLaunchAtLoginBootstrapsOnEnable() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/ClaudePulse/LaunchAtLoginManager.swift"),
            encoding: .utf8
        )

        #expect(source.contains("\"RunAtLoad\": true"))
        #expect(source.contains("\"bootstrap\""))
    }

    @Test
    func testPackagingScriptsEmitSha256Checksums() throws {
        let root = packageRoot()

        for script in ["scripts/package-dmg.sh", "scripts/package-zip.sh"] {
            let source = try String(
                contentsOf: root.appendingPathComponent(script),
                encoding: .utf8
            )

            #expect(source.contains("shasum -a 256"))
            #expect(source.contains(".sha256"))
        }
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
            resetDisplay: .relative,
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
    func testFormatterIsDrivenEntirelyByInjectedStrings() {
        // There is one formatter; localisation is data. Swapping the strings bag
        // must change every rendered surface, with no English leaking through.
        let now = Date(timeIntervalSince1970: 1_778_719_500)
        let translated = UsageFormatStrings(
            unavailable: "KO_unavailable",
            limited: "KO_limited",
            stale: "KO_stale",
            low: "KO_low",
            fiveHourShort: "KO_5h",
            weeklyShort: "KO_W",
            percentUnknown: "KO_?",
            percentRemaining: "KO_%d",
            percentUsed: "KO_%d_used",
            percentRemainingAndUsed: "KO_%d_%d",
            resetUnknown: "KO_unknown",
            resetAbsoluteAndRelative: "%@ [%@]",
            relativeNow: "KO_now",
            relativeDayHourUntil: "KO_%dd%dh",
            relativeHourMinuteUntil: "KO_%dh%dm",
            relativeMinuteUntil: "KO_%dm",
            relativeDayHourAgo: "KO_%dd%dh_ago",
            relativeHourMinuteAgo: "KO_%dh%dm_ago",
            relativeMinuteAgo: "KO_%dm_ago",
            detailWindow: "%@ | %d | %@ | %d",
            detailWindowUnavailable: "%@ | KO_unavailable"
        )
        let window = UsageWindow(usedPercent: 9, windowDurationMins: 300, resetsAt: 1_778_736_433)
        let data = UsageData(
            snapshot: UsageSnapshot(planType: nil, primary: window, secondary: window, usageReachedType: nil),
            additionalLimits: [:],
            source: .claudeAPI,
            fetchedAt: now
        )

        #expect(DisplayFormatter.statusTitle(for: data, mode: .both, now: now, strings: translated, locale: enGB)
            == "KO_5h KO_91 KO_W KO_91")
        #expect(DisplayFormatter.detailLine(label: "L", window: window, resetDisplay: .both, now: now, strings: translated, locale: enGB)
            == "L | 91 | 13:27 [KO_4h42m] | 9")
        #expect(DisplayFormatter.detailLine(label: "L", window: nil, strings: translated) == "L | KO_unavailable")
        #expect(DisplayFormatter.percentText(nil, strings: translated) == "KO_?")
        #expect(DisplayFormatter.relativeAge(Date(timeIntervalSince1970: 1_778_719_200), now: now, strings: translated)
            == "KO_5m_ago")
        #expect(DisplayFormatter.statusTitle(for: nil, mode: .both, strings: translated) == "KO_unavailable")
    }

    @Test
    func testResetTextFormats() {
        let now = Date(timeIntervalSince1970: 1_778_719_500)
        let sameDay = 1_778_736_433      // 4h 42m out
        let futureDay = 1_779_152_172    // 5d 0h out

        #expect(DisplayFormatter.resetText(sameDay, display: .absolute, now: now, locale: enGB) == "13:27")
        #expect(DisplayFormatter.resetText(sameDay, display: .relative, now: now, locale: enGB) == "in 4h 42m")
        #expect(DisplayFormatter.resetText(sameDay, display: .both, now: now, locale: enGB) == "13:27 (in 4h 42m)")

        #expect(DisplayFormatter.resetText(futureDay, display: .absolute, now: now, locale: enGB) == "19 May")
        #expect(DisplayFormatter.resetText(futureDay, display: .relative, now: now, locale: enGB) == "in 5d 0h")
        #expect(DisplayFormatter.resetText(futureDay, display: .both, now: now, locale: enGB) == "19 May (in 5d 0h)")

        #expect(DisplayFormatter.resetText(nil, display: .relative, now: now, locale: enGB) == "unknown")
    }

    @Test
    func testRelativeResetHandlesMinutesAndElapsedWindows() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(DisplayFormatter.relativeUntil(Date(timeIntervalSince1970: 1_000_900), now: now) == "in 15m")
        // A window whose reset already passed counts as "now", never negative.
        #expect(DisplayFormatter.relativeUntil(Date(timeIntervalSince1970: 999_000), now: now) == "now")
        #expect(DisplayFormatter.relativeUntil(Date(timeIntervalSince1970: 1_000_000), now: now) == "now")
    }

    @Test
    func testDetailLineHonoursResetDisplay() {
        let now = Date(timeIntervalSince1970: 1_778_719_500)
        let window = UsageWindow(usedPercent: 9, windowDurationMins: 300, resetsAt: 1_778_736_433)

        #expect(DisplayFormatter.detailLine(label: "5-hour window", window: window, resetDisplay: .relative, now: now, locale: enGB)
            == "5-hour window: 91% remaining, resets in 4h 42m (9% used)")
        #expect(DisplayFormatter.detailLine(label: "5-hour window", window: window, resetDisplay: .both, now: now, locale: enGB)
            == "5-hour window: 91% remaining, resets 13:27 (in 4h 42m) (9% used)")
    }

    @Test
    func testSettingsSavedBeforeResetDisplayExistedStillLoad() throws {
        let suiteName = "ClaudePulseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Exactly what an older build wrote: no resetDisplay key at all. It must
        // not blow away the rest of the user's saved preferences.
        let legacy = """
        {"displayMode":"weekly","percentDisplay":"used","refreshInterval":300,
         "appLanguage":"english","notificationsEnabled":true,
         "notifyFiveHourThresholds":[10],"notifyWeeklyThresholds":[20],
         "staleAfterMinutes":45}
        """
        defaults.set(Data(legacy.utf8), forKey: "claudePulseSettings")

        let loaded = ClaudePulseSettings.load(from: defaults)
        #expect(loaded.resetDisplay == .absolute)
        #expect(loaded.displayMode == .weekly)
        #expect(loaded.percentDisplay == .used)
        #expect(loaded.refreshInterval == .fiveMinutes)
        #expect(loaded.staleAfterMinutes == 45)
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

        #expect(DisplayFormatter.resetText(sameDay, now: now, locale: enGB) == "13:27")
        #expect(DisplayFormatter.resetText(futureDay, now: now, locale: enGB) == "19 May")
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

        #expect(data.snapshot.planType == "Prolite")
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
    func testUsagePayloadCarriesNoPlanSoPlanTypeStaysNil() throws {
        // The live /usage response has no plan field at all. Guard the assumption
        // that the plan has to come from the organizations endpoint instead.
        let json = """
        {
          "five_hour": {"utilization": 3.0, "resets_at": "2026-06-22T06:39:59Z"},
          "seven_day": {"utilization": 44.0, "resets_at": "2026-06-28T21:59:59Z"}
        }
        """
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let data = try ClaudeUsagePayloadParser.parse(result: object, source: .claudeAPI)

        #expect(data.snapshot.planType == nil)
    }

    @Test
    func testResolvesPlanNameFromOrganizationsPayload() throws {
        let json = """
        [
          {"uuid": "other-org", "rate_limit_tier": "default_pro"},
          {"uuid": "my-org", "rate_limit_tier": "default_claude_max_20x"}
        ]
        """
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))

        #expect(ClaudePlanResolver.planName(inOrganizationsPayload: object, organizationID: "my-org") == "Max 20x")
        #expect(ClaudePlanResolver.planName(inOrganizationsPayload: object, organizationID: "other-org") == "Pro")
        #expect(ClaudePlanResolver.planName(inOrganizationsPayload: object, organizationID: "missing") == nil)
    }

    @Test
    func testResolvesPlanNameFromCapabilitiesWhenTierIsAbsent() throws {
        let json = """
        {"organizations": [{"uuid": "my-org", "capabilities": ["chat", "claude_max"]}]}
        """
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))

        #expect(ClaudePlanResolver.planName(inOrganizationsPayload: object, organizationID: "my-org") == "Max")
    }

    @Test
    func testPlanTierDisplayNames() {
        #expect(ClaudePlanResolver.displayName(forTier: "default_claude_max_5x") == "Max 5x")
        #expect(ClaudePlanResolver.displayName(forTier: "default_claude_max_20x") == "Max 20x")
        #expect(ClaudePlanResolver.displayName(forTier: "default_free") == "Free")
        #expect(ClaudePlanResolver.displayName(forTier: "raven") == "Team")
        #expect(ClaudePlanResolver.displayName(forTier: "") == nil)
        // An unrecognised tier is prettified rather than dropped.
        #expect(ClaudePlanResolver.displayName(forTier: "default_something_new") == "Something New")
        // Whole-token matching: "prolite" is its own tier, not Pro.
        #expect(ClaudePlanResolver.displayName(forTier: "prolite") == "Prolite")
    }

    @Test
    func testDiscoversFableAndOtherModelSpecificLimits() throws {
        // Fable bills against its own weekly limit, separate from the shared pool
        // in `seven_day`. New model buckets must be picked up without a code change.
        let json = """
        {
          "five_hour": {"utilization": 3.0, "resets_at": "2026-06-22T06:39:59Z"},
          "seven_day": {"utilization": 44.0, "resets_at": "2026-06-28T21:59:59Z"},
          "seven_day_fable": {"utilization": 61.0, "resets_at": "2026-06-28T21:59:59Z"},
          "seven_day_opus": null,
          "seven_day_sonnet": {"utilization": 12.4, "resets_at": "2026-06-28T21:59:59Z"},
          "seven_day_some_future_model": {"utilization": 5.0, "resets_at": "2026-06-28T21:59:59Z"},
          "extra_usage": {"is_enabled": false, "monthly_limit": null, "utilization": null}
        }
        """
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let data = try ClaudeUsagePayloadParser.parse(result: object, source: .claudeAPI)

        #expect(data.snapshot.primary?.usedPercent == 3)
        #expect(data.snapshot.secondary?.usedPercent == 44)
        #expect(data.additionalLimits["seven_day_fable"]?.secondary?.usedPercent == 61)
        #expect(data.additionalLimits["seven_day_some_future_model"]?.secondary?.usedPercent == 5)
        // Null buckets and windowless objects must not become phantom limits.
        #expect(data.additionalLimits["seven_day_opus"] == nil)
        #expect(data.additionalLimits["extra_usage"] == nil)

        let display = data.additionalLimitsForDisplay
        #expect(display.map(\.label) == ["Fable", "Some Future Model", "Sonnet"])
        #expect(display.allSatisfy { $0.kind == .weekly })
        #expect(display.first?.window.remainingPercent == 39)
    }

    @Test
    func testParsesLiveUsagePayloadShape() throws {
        // Trimmed from a real /api/organizations/<uuid>/usage response. The codenamed
        // buckets and the non-resetting credit pools are the parts that trip up
        // generic window discovery.
        let json = """
        {
          "five_hour": {"utilization": 3.0, "used_dollars": 1.2, "limit_dollars": 40.0, "resets_at": "2026-08-01T06:39:59Z"},
          "seven_day": {"utilization": 44.0, "used_dollars": 88.0, "limit_dollars": 200.0, "resets_at": "2026-08-05T21:59:59Z"},
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "seven_day_cowork": null,
          "seven_day_oauth_apps": null,
          "seven_day_omelette": null,
          "omelette_promotional": null,
          "amber_ladder": null,
          "tangelo": null,
          "member_dashboard_available": true,
          "limits": [],
          "extra_usage": {"is_enabled": true, "utilization": 12.0, "monthly_limit": 50, "used_credits": 6},
          "spend": {"enabled": true, "percent": 30, "used": 15, "limit": 50, "balance": 35}
        }
        """
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let data = try ClaudeUsagePayloadParser.parse(result: object, source: .claudeAPI)

        // The top-level `limits` array must not be mistaken for a usage container.
        #expect(data.snapshot.primary?.usedPercent == 3)
        #expect(data.snapshot.secondary?.usedPercent == 44)
        #expect(data.snapshot.planType == nil)

        // Credit pools expose a percentage but never reset, so they are not windows.
        #expect(data.additionalLimits["spend"] == nil)
        #expect(data.additionalLimitsForDisplay.isEmpty)
    }

    @Test
    func testMainWindowKeysAreNotDuplicatedAsAdditionalLimits() throws {
        let json = """
        {
          "five_hour": {"utilization": 3.0},
          "seven_day": {"utilization": 44.0}
        }
        """
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let data = try ClaudeUsagePayloadParser.parse(result: object, source: .claudeAPI)

        #expect(data.additionalLimits.isEmpty)
        #expect(data.additionalLimitsForDisplay.isEmpty)
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
        #expect(data.snapshot.planType == "Max")
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
        #expect(data.snapshot.planType != nil, "plan should resolve from /api/organizations")
        print("LIVE plan=\(data.snapshot.planType ?? "nil") extras=\(data.additionalLimitsForDisplay.map(\.label))")
    }

    /// Pinned so date rendering does not depend on the machine's region setting.
    private let enGB = Locale(identifier: "en_GB")

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
