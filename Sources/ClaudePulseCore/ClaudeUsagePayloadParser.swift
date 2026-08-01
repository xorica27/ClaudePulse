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
            snapshot: snapshot,
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
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func parseSnapshot(_ bucket: [String: Any]) -> UsageSnapshot {
        UsageSnapshot(
            planType: firstString(bucket, keys: ["planType", "plan_type", "tier", "product", "product_name"]),
            primary: parseFirstWindow(bucket, keys: [
                "primary", "fiveHour", "five_hour", "5h", "shortWindow", "short_window",
                "planUsage", "plan_usage", "usageCredits", "usage_credits"
            ]) ?? parseWindow(bucket),
            secondary: parseFirstWindow(bucket, keys: [
                "secondary", "weekly", "week", "seven_day", "longWindow", "long_window", "allModels", "all_models"
            ]),
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
        for key in [
            "seven_day_opus",
            "seven_day_sonnet",
            "seven_day_oauth_apps",
            "seven_day_cowork",
            "seven_day_omelette",
            "omelette_promotional"
        ] {
            guard let value = bucket[key] as? [String: Any] else {
                continue
            }
            let snapshot = UsageSnapshot(
                planType: nil,
                primary: nil,
                secondary: parseWindow(value),
                usageReachedType: nil
            )
            if snapshot.secondary != nil {
                additional[key] = snapshot
            }
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
