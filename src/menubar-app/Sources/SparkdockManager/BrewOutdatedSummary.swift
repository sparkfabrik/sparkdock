import Foundation

/// Counts from the line `sparkdock-check-updates brew` prints when packages are outdated.
struct BrewOutdatedSummary: Equatable {
    let formulae: Int
    let casks: Int

    var total: Int { formulae + casks }

    /// Maps one run of `sparkdock-check-updates brew` to the row state and its counts.
    /// Outdated packages without a readable summary are unavailable, not up to date.
    static func status(exitCode: Int32?, output: String) -> (status: CheckStatus, summary: BrewOutdatedSummary?) {
        let status = CheckStatus.from(exitCode: exitCode)
        guard status.needsAction else { return (status, nil) }
        guard let summary = parse(output) else { return (.unavailable, nil) }
        return (.needsAttention(badge: "Upgrade (\(summary.total))"), summary)
    }

    /// Parses "Homebrew: 11 formulae, 6 casks outdated"; nil when no line matches.
    static func parse(_ output: String) -> BrewOutdatedSummary? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.wholeMatch(of: #/Homebrew: (\d+) formulae, (\d+) casks outdated/#),
               let formulae = Int(match.1), let casks = Int(match.2) {
                return BrewOutdatedSummary(formulae: formulae, casks: casks)
            }
        }
        return nil
    }
}
