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
            return "Sign in required"
        case "expired":
            return "Credentials expired"
        case "valid":
            break
        default:
            return "Unavailable"
        }

        if error != nil && currentPercent == 0 && weeklyPercent == 0 {
            return "Unavailable"
        }

        return ""
    }

    var isAvailable: Bool {
        availabilityText.isEmpty
    }

    var currentResetText: String? {
        Self.formattedReset(currentReset)
    }

    var weeklyResetText: String? {
        Self.formattedReset(weeklyReset)
    }

    private static func formattedReset(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty && value != "?" else { return nil }

        var parts: [String] = []
        var index = value.startIndex
        var prefix = ""

        while index < value.endIndex {
            while index < value.endIndex && value[index].isWhitespace {
                value.formIndex(after: &index)
            }
            guard index < value.endIndex else { break }

            if value[index] == "<" {
                prefix = "<"
                value.formIndex(after: &index)
            }

            var digits = ""
            while index < value.endIndex && value[index].isNumber {
                digits.append(value[index])
                value.formIndex(after: &index)
            }

            var unit = ""
            while index < value.endIndex && value[index].isLetter {
                unit.append(value[index])
                value.formIndex(after: &index)
            }

            guard !digits.isEmpty && !unit.isEmpty else { return value }
            parts.append("\(prefix)\(Int(digits) ?? 0)\(unit)")
            prefix = ""
        }

        return parts.joined(separator: " ")
    }
}
