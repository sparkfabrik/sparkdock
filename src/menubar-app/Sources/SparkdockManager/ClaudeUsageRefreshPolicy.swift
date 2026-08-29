import Foundation

/// Decides whether opening the menu should trigger a Claude usage recheck.
///
/// Usage checks are event-driven (system wake and network change), and the menu
/// is the only surface for the result. Without a refresh on open, a menu opened
/// hours after the last event shows whatever that event produced -- including an
/// `auth: expired` reading that the OAuth token refresh has long since made
/// obsolete.
enum ClaudeUsageRefreshPolicy {
    /// Matches the window `claude-usage` caches its own quota poll for: a
    /// recheck inside it would re-read the same cached file.
    static let minimumInterval: TimeInterval = 60

    static func shouldRefresh(lastCheckedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastCheckedAt = lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= minimumInterval
    }
}
