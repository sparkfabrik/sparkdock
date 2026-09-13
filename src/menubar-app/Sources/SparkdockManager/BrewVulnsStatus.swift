import Foundation

/// Result of `sparkdock-check-updates vulns`: exit 0 with findings, 1 with none,
/// 3 when Homebrew is missing or older than the 7 that added `brew vulns`.
enum BrewVulnsStatus: Equatable {
    /// No answer: Homebrew missing or older than 7, or the check failed.
    case unavailable
    /// Checked, nothing found.
    case clean
    /// Findings, with the badge text for the status row.
    case findings(String)

    /// Maps one run of the subcommand to a status.
    static func from(exitCode: Int32?, output: String) -> BrewVulnsStatus {
        switch exitCode {
        case .some(0):
            return .findings(badge(from: output) ?? "Found")
        case .some(1):
            return .clean
        default:
            return .unavailable
        }
    }

    /// Condenses "Homebrew vulnerabilities: 4 in 2 formulae, 2 high or critical"
    /// into the compact badge "4, 2 high".
    static func badge(from output: String) -> String? {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.first(where: { !$0.isEmpty }) else { return nil }
        let summary = line.replacingOccurrences(of: "Homebrew vulnerabilities: ", with: "")
        let parts = summary.components(separatedBy: ", ")
        guard let total = parts.first?.components(separatedBy: " ").first, !total.isEmpty else { return nil }
        guard parts.count > 1, let severe = parts[1].components(separatedBy: " ").first, severe != "0" else {
            return total
        }
        return "\(total), \(severe) high"
    }
}
