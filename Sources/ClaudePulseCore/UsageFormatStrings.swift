import Foundation

/// The format strings `DisplayFormatter` needs, resolved by the caller.
///
/// The app builds one of these from its `.strings` bundles; Core falls back to
/// `.english`. Injecting resolved strings rather than a lookup closure keeps the
/// formatter free of any localisation machinery — and keeps it usable from
/// outside the main actor, which a `Bundle`-backed lookup would not be.
public struct UsageFormatStrings: Sendable {
    public let unavailable: String
    public let limited: String
    public let stale: String
    public let low: String
    public let fiveHourShort: String
    public let weeklyShort: String

    public let percentUnknown: String
    public let percentRemaining: String
    public let percentUsed: String
    public let percentRemainingAndUsed: String

    public let resetUnknown: String
    public let resetAbsoluteAndRelative: String
    public let resetTimeTemplate: String
    public let resetDateTemplate: String

    public let relativeNow: String
    public let relativeDayHourUntil: String
    public let relativeHourMinuteUntil: String
    public let relativeMinuteUntil: String
    public let relativeDayHourAgo: String
    public let relativeHourMinuteAgo: String
    public let relativeMinuteAgo: String

    public let detailWindow: String
    public let detailWindowUnavailable: String

    public init(
        unavailable: String,
        limited: String,
        stale: String,
        low: String,
        fiveHourShort: String,
        weeklyShort: String,
        percentUnknown: String,
        percentRemaining: String,
        percentUsed: String,
        percentRemainingAndUsed: String,
        resetUnknown: String,
        resetAbsoluteAndRelative: String,
        relativeNow: String,
        relativeDayHourUntil: String,
        relativeHourMinuteUntil: String,
        relativeMinuteUntil: String,
        relativeDayHourAgo: String,
        relativeHourMinuteAgo: String,
        relativeMinuteAgo: String,
        detailWindow: String,
        detailWindowUnavailable: String,
        // Date *templates*, not patterns: DateFormatter reorders and adapts them
        // per locale, so these stay the same in every language.
        resetTimeTemplate: String = "HH:mm",
        resetDateTemplate: String = "d MMM"
    ) {
        self.unavailable = unavailable
        self.limited = limited
        self.stale = stale
        self.low = low
        self.fiveHourShort = fiveHourShort
        self.weeklyShort = weeklyShort
        self.percentUnknown = percentUnknown
        self.percentRemaining = percentRemaining
        self.percentUsed = percentUsed
        self.percentRemainingAndUsed = percentRemainingAndUsed
        self.resetUnknown = resetUnknown
        self.resetAbsoluteAndRelative = resetAbsoluteAndRelative
        self.relativeNow = relativeNow
        self.relativeDayHourUntil = relativeDayHourUntil
        self.relativeHourMinuteUntil = relativeHourMinuteUntil
        self.relativeMinuteUntil = relativeMinuteUntil
        self.relativeDayHourAgo = relativeDayHourAgo
        self.relativeHourMinuteAgo = relativeHourMinuteAgo
        self.relativeMinuteAgo = relativeMinuteAgo
        self.detailWindow = detailWindow
        self.detailWindowUnavailable = detailWindowUnavailable
        self.resetTimeTemplate = resetTimeTemplate
        self.resetDateTemplate = resetDateTemplate
    }

    /// Mirrors `en.lproj/Localizable.strings`. Used by Core callers and tests that
    /// have no bundle to read from.
    public static let english = UsageFormatStrings(
        unavailable: "Usage unavailable",
        limited: "limited",
        stale: "stale",
        low: "low",
        fiveHourShort: "5h",
        weeklyShort: "W",
        percentUnknown: "?%",
        percentRemaining: "%d%%",
        percentUsed: "%d%% used",
        percentRemainingAndUsed: "%d%% rem/%d%% used",
        resetUnknown: "unknown",
        resetAbsoluteAndRelative: "%@ (%@)",
        relativeNow: "now",
        relativeDayHourUntil: "in %dd %dh",
        relativeHourMinuteUntil: "in %dh %dm",
        relativeMinuteUntil: "in %dm",
        relativeDayHourAgo: "%dd %dh ago",
        relativeHourMinuteAgo: "%dh %dm ago",
        relativeMinuteAgo: "%dm ago",
        detailWindow: "%@: %d%% remaining, resets %@ (%d%% used)",
        detailWindowUnavailable: "%@: unavailable"
    )
}
