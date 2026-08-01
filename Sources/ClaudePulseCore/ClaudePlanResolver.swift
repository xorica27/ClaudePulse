import Foundation

/// Resolves a human-readable Claude plan name from the organizations payload.
///
/// `/api/organizations/<uuid>/usage` only carries rate-limit windows, so the plan
/// has to come from the organization record itself. Which field holds it has moved
/// around between `rate_limit_tier`, `capabilities`, and `organization_type`, so we
/// probe them in specificity order rather than betting on one name.
public enum ClaudePlanResolver {
    public static func planName(inOrganizationsPayload object: Any, organizationID: String) -> String? {
        guard let organization = organization(in: object, id: organizationID) else {
            return nil
        }
        return planName(inOrganization: organization)
    }

    public static func planName(inOrganization organization: [String: Any]) -> String? {
        if let tier = firstString(organization, keys: ["rate_limit_tier", "rateLimitTier"]) {
            return displayName(forTier: tier)
        }

        if let capabilities = organization["capabilities"] as? [Any],
           let name = displayName(forCapabilities: capabilities.compactMap { $0 as? String }) {
            return name
        }

        if let settings = organization["settings"] as? [String: Any],
           let tier = firstString(settings, keys: ["rate_limit_tier", "tier", "plan"]) {
            return displayName(forTier: tier)
        }

        if let type = firstString(organization, keys: [
            "organization_type", "organizationType", "plan_type", "planType", "product", "product_name"
        ]) {
            return displayName(forTier: type)
        }

        return nil
    }

    /// Maps a raw tier string such as `default_claude_max_20x` onto a display name.
    public static func displayName(forTier rawTier: String) -> String? {
        guard !rawTier.isEmpty else {
            return nil
        }

        // Match whole tokens, not substrings, so a distinct tier like "prolite"
        // is not silently collapsed into "Pro".
        let tokens = Set(
            rawTier.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        if tokens.contains("max") {
            if tokens.contains("20x") {
                return "Max 20x"
            }
            if tokens.contains("5x") {
                return "Max 5x"
            }
            return "Max"
        }
        if tokens.contains("enterprise") {
            return "Enterprise"
        }
        if tokens.contains("team") || tokens.contains("raven") {
            return "Team"
        }
        if tokens.contains("pro") {
            return "Pro"
        }
        if tokens.contains("free") {
            return "Free"
        }

        // An unrecognised tier is still more useful than "unknown".
        return prettified(rawTier)
    }

    static func organization(in object: Any, id: String) -> [String: Any]? {
        let organizations: [[String: Any]]
        switch object {
        case let array as [Any]:
            organizations = array.compactMap { $0 as? [String: Any] }
        case let dictionary as [String: Any]:
            if let nested = dictionary["organizations"] as? [Any] {
                organizations = nested.compactMap { $0 as? [String: Any] }
            } else {
                organizations = [dictionary]
            }
        default:
            return nil
        }

        if let match = organizations.first(where: { firstString($0, keys: ["uuid", "id"]) == id }) {
            return match
        }
        // A single-organization account still resolves even if the id shape changes.
        return organizations.count == 1 ? organizations.first : nil
    }

    private static func displayName(forCapabilities capabilities: [String]) -> String? {
        let values = Set(capabilities.map { $0.lowercased() })
        if values.contains("claude_max") {
            return "Max"
        }
        if values.contains("enterprise") {
            return "Enterprise"
        }
        if values.contains("raven") {
            return "Team"
        }
        if values.contains("claude_pro") {
            return "Pro"
        }
        return nil
    }

    private static func prettified(_ raw: String) -> String {
        var value = raw
        for prefix in ["default_", "claude_"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        let words = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? raw : words.joined(separator: " ")
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
