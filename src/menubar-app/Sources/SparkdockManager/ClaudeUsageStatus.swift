import Foundation

struct ClaudeUsageStatus: Decodable, Equatable {
    let currentPercent: Int
    let currentReset: String
    let weeklyPercent: Int
    let weeklyReset: String
    let stale: Bool
    let auth: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case currentPercent = "c_pct"
        case currentReset = "c_reset"
        case weeklyPercent = "w_pct"
        case weeklyReset = "w_reset"
        case stale
        case auth
        case error
    }

    var availabilityText: String {
        switch auth {
        case "missing":
            return "Claude Code usage: sign in required"
        case "expired":
            return "Claude Code usage: credentials expired"
        case "valid":
            break
        default:
            return "Claude Code usage: unavailable"
        }

        if error != nil && currentPercent == 0 && weeklyPercent == 0 {
            return "Claude Code usage: unavailable"
        }

        return ""
    }

    var isAvailable: Bool {
        availabilityText.isEmpty
    }

    var currentDisplayText: String {
        var text = "Current session (5h): \(currentPercent)%"
        if currentReset != "?" && !currentReset.isEmpty {
            text += " · resets in \(currentReset)"
        }
        if stale {
            text += " [stale]"
        }
        return text
    }

    var weeklyDisplayText: String {
        var text = "Weekly limit (7d): \(weeklyPercent)%"
        if weeklyReset != "?" && !weeklyReset.isEmpty {
            text += " · resets in \(weeklyReset)"
        }
        if stale {
            text += " [stale]"
        }
        return text
    }
}
