import Foundation

/// Badge text from the line `sparkdock-check-updates vulns` prints when it finds vulnerabilities.
enum BrewVulnsSummary {
    /// Maps one run of `sparkdock-check-updates vulns` to the row state. Findings are
    /// not a pending update, so the caller keeps them out of the icon tint.
    static func status(exitCode: Int32?, output: String) -> CheckStatus {
        switch CheckStatus.from(exitCode: exitCode) {
        case .retry:
            return .retry
        case .needsAttention:
            return .needsAttention(badge: badge(from: output) ?? "Found")
        case .ok:
            return .ok(badge: "None")
        case let status:
            return status
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
