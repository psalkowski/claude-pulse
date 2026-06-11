import Foundation

// Derives the display label from authoritative /api/oauth/profile fields.
// IMPORTANT: Anthropic exposes no human-readable seat name anywhere — the only
// machine fields are `organization_type`, `rate_limit_tier` (e.g.
// "default_claude_max_5x"/"_20x"/"default_raven") and the opaque `seat_tier`
// ("team_tier_1"). For Team orgs the seat (Standard 1.25× Pro vs Premium 6.25×
// Pro, per support.claude.com/9266767) is therefore DERIVED from the rate band:
// the high band (max_5x/max_20x/raven) is the Premium seat, anything lower is
// Standard. No string is invented from `seat_tier`.
enum PlanLabel {
    static func make(from profile: AccountProfile) -> (title: String, detail: String?) {
        let type = profile.organizationType ?? ""
        switch type {
        case "claude_max":
            return (rateBand(profile.rateLimitTier) ?? "Max", profile.email)
        case "claude_pro":
            return ("Pro", profile.email)
        case "claude_team", "claude_enterprise":
            let org = profile.organizationName?.isEmpty == false
                ? profile.organizationName! : humanize(type) ?? "Team"
            return (org, teamDetail(profile))
        default:
            if let org = profile.organizationName, !org.isEmpty {
                return (org, rateBand(profile.rateLimitTier))
            }
            if profile.hasClaudeMax { return ("Max", profile.email) }
            if profile.hasClaudePro { return ("Pro", profile.email) }
            return (humanize(type) ?? "Claude", profile.email)
        }
    }

    private static func teamDetail(_ profile: AccountProfile) -> String? {
        var parts: [String] = []
        if let seat = seatName(rateTier: profile.rateLimitTier) { parts.append(seat) }
        if let band = rateBand(profile.rateLimitTier) { parts.append("\(band) limits") }
        return parts.isEmpty ? profile.email : parts.joined(separator: " · ")
    }

    // Map the rate band to the official Team seat name. Premium = 6.25× Pro
    // (the high usage band); Standard = 1.25× Pro (the low band).
    private static func seatName(rateTier: String?) -> String? {
        guard let tier = rateTier?.lowercased() else { return nil }
        if tier.contains("raven") || rateMultiplier(tier).map({ $0 >= 5 }) == true {
            return "Premium seat"
        }
        if rateMultiplier(tier) != nil || tier.contains("claude_ai") {
            return "Standard seat"
        }
        return nil
    }

    // "default_claude_max_5x" / "..._x5" → "Max 5×"
    static func rateBand(_ raw: String?) -> String? {
        guard let mult = rateMultiplier(raw) else {
            if raw?.lowercased().contains("raven") == true { return "Team" }
            return nil
        }
        return "Max \(mult)×"
    }

    private static func rateMultiplier(_ raw: String?) -> Int? {
        guard let text = raw?.lowercased(), let range = text.range(of: "max") else { return nil }
        let tail = text[range.upperBound...]
        let digits = tail.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    static func humanize(_ raw: String?) -> String? {
        guard var text = raw, !text.isEmpty else { return nil }
        for prefix in ["default_", "claude_"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        text = text.replacingOccurrences(of: "_", with: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
