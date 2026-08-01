import Foundation

public enum ClaudeUsagePayloadParser {
    public static func parse(
        result: [String: Any],
        source: UsageSource,
        sourcePath: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> UsageData {
        let root = firstUsageContainer(in: result) ?? result
        let snapshot = parseSnapshot(root)
        guard snapshot.primary != nil || snapshot.secondary != nil else {
            throw ClaudeUsageError.malformedResponse
        }

        return UsageData(
            snapshot: snapshot.withPlanType(snapshot.planType.flatMap(ClaudePlanResolver.displayName(forTier:))),
            additionalLimits: parseAdditionalUsage(from: root),
            source: source,
            sourcePath: sourcePath,
            fetchedAt: fetchedAt
        )
    }

    private static func firstUsageContainer(in object: [String: Any]) -> [String: Any]? {
        for key in [
            "usage",
            "usages",
            "plan_usage",
            "planUsage",
            "usageCredits",
            "usage_credits",
            "usage_limits",
            "usageLimits",
            "quota",
            "limits"
        ] {
            // Only pivot into a container that actually holds windows. The live
            // usage response has a top-level `limits` key that is an array today;
            // if it ever became an object, blindly descending would drop
            // `five_hour` and `seven_day` on the floor.
            if let value = object[key] as? [String: Any] {
                let candidate = parseSnapshot(value)
                if candidate.primary != nil || candidate.secondary != nil {
                    return value
                }
            }
        }
        return nil
    }

    private static let primaryWindowKeys = [
        "primary", "fiveHour", "five_hour", "5h", "shortWindow", "short_window",
        "planUsage", "plan_usage", "usageCredits", "usage_credits"
    ]

    private static let secondaryWindowKeys = [
        "secondary", "weekly", "week", "seven_day", "longWindow", "long_window", "allModels", "all_models"
    ]

    /// Keys already consumed as the two headline windows, so they are not also
    /// reported as model-specific extras.
    private static let mainWindowKeys = Set(primaryWindowKeys + secondaryWindowKeys)

    private static func isFiveHourKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("five_hour")
            || normalized.contains("fivehour")
            || normalized.contains("5h")
    }

    private static func parseSnapshot(_ bucket: [String: Any]) -> UsageSnapshot {
        UsageSnapshot(
            planType: firstString(bucket, keys: [
                "planType", "plan_type", "tier", "rate_limit_tier", "rateLimitTier",
                "subscription", "subscription_type", "product", "product_name"
            ]),
            primary: parseFirstWindow(bucket, keys: primaryWindowKeys) ?? parseWindow(bucket),
            secondary: parseFirstWindow(bucket, keys: secondaryWindowKeys),
            usageReachedType: firstString(bucket, keys: [
                "usageReachedType", "usage_reached_type", "limitReachedType", "limit_reached_type"
            ])
        )
    }

    private static func parseAdditionalUsage(from bucket: [String: Any]) -> [String: UsageSnapshot] {
        var additional: [String: UsageSnapshot] = [:]
        for key in ["extra", "extraUsage", "extra_usage", "overage", "additional", "additional_usage"] {
            guard let value = bucket[key] as? [String: Any] else {
                continue
            }
            let snapshot = parseSnapshot(value)
            if snapshot.primary != nil || snapshot.secondary != nil {
                additional[key] = snapshot
            }
        }
        // Model- and feature-specific buckets appear and disappear as models ship,
        // and the live response carries several under rotating internal codenames
        // alongside seven_day_opus/sonnet/cowork. Discover any sibling that looks
        // like a window instead of maintaining a fixed list that silently drops new
        // ones — that is how Fable's separate weekly limit gets picked up without
        // knowing its key in advance.
        //
        // A reset timestamp is what separates a rate-limit window from the credit
        // pools in the same payload: `spend` has a `percent` and `extra_usage` has a
        // `utilization`, but neither resets, and neither is a rate limit.
        for (key, value) in bucket {
            guard additional[key] == nil,
                  !Self.mainWindowKeys.contains(key),
                  let object = value as? [String: Any],
                  let window = parseWindow(object),
                  window.resetsAt != nil else {
                continue
            }

            let isFiveHour = Self.isFiveHourKey(key)
            additional[key] = UsageSnapshot(
                planType: nil,
                primary: isFiveHour ? window : nil,
                secondary: isFiveHour ? nil : window,
                usageReachedType: nil
            )
        }
        for key in ["usagesByLimitId", "usageByLimitId", "usage_by_limit_id"] {
            guard let values = bucket[key] as? [String: Any] else {
                continue
            }
            for (name, value) in values {
                guard let object = value as? [String: Any] else {
                    continue
                }
                let snapshot = parseSnapshot(object)
                if snapshot.primary != nil || snapshot.secondary != nil {
                    additional[firstString(object, keys: ["limitName", "limit_name", "name"]) ?? name] = snapshot
                }
            }
        }
        return additional
    }

    private static func parseFirstWindow(_ bucket: [String: Any], keys: [String]) -> UsageWindow? {
        for key in keys {
            if let window = parseWindow(bucket[key] as? [String: Any]) {
                return window
            }
        }
        return nil
    }

    private static func parseWindow(_ value: [String: Any]?) -> UsageWindow? {
        guard let value else {
            return nil
        }

        let usedPercent = firstInt(value, keys: [
            "usedPercent", "used_percent", "percentUsed", "percent_used", "pct", "percentage", "percent", "utilization"
        ]) ?? percentFromUsedAndLimit(value)
        guard let usedPercent else {
            return nil
        }

        return UsageWindow(
            usedPercent: usedPercent,
            windowDurationMins: firstInt(value, keys: [
                "windowDurationMins", "window_minutes", "windowMins", "durationMinutes"
            ]),
            resetsAt: firstEpoch(value, keys: [
                "resetsAt", "resets_at", "resetAt", "reset_at", "resets", "reset"
            ])
        )
    }

    private static func percentFromUsedAndLimit(_ value: [String: Any]) -> Int? {
        guard let used = firstDouble(value, keys: ["used", "current", "consumed"]),
              let limit = firstDouble(value, keys: ["limit", "max", "total"]),
              limit > 0 else {
            return nil
        }
        return Int((used / limit * 100).rounded())
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstInt(_ object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int {
                return value
            }
            if let value = object[key] as? Double {
                return Int(value.rounded())
            }
            if let value = object[key] as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if let parsed = Int(cleaned) {
                    return parsed
                }
                if let parsed = Double(cleaned) {
                    return Int(parsed.rounded())
                }
            }
        }
        return nil
    }

    private static func firstDouble(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double {
                return value
            }
            if let value = object[key] as? Int {
                return Double(value)
            }
            if let value = object[key] as? String,
               let parsed = Double(value.replacingOccurrences(of: ",", with: "")) {
                return parsed
            }
        }
        return nil
    }

    private static func firstEpoch(_ object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int {
                return normalizeEpoch(value)
            }
            if let value = object[key] as? Double {
                return normalizeEpoch(Int(value.rounded()))
            }
            if let value = object[key] as? String {
                if let intValue = Int(value) {
                    return normalizeEpoch(intValue)
                }
                if let date = ISO8601DateFormatter().date(from: value) {
                    return Int(date.timeIntervalSince1970)
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: value) {
                    return Int(date.timeIntervalSince1970)
                }
            }
        }
        return nil
    }

    private static func normalizeEpoch(_ value: Int) -> Int {
        value > 10_000_000_000 ? value / 1_000 : value
    }
}
