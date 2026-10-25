import Foundation

/// State of one System status row, from one run of `sparkdock-check-updates`.
enum CheckStatus: Equatable {
    /// Exit 0: something to act on, with an optional badge in place of "Upgrade".
    case needsAttention(badge: String?)
    /// Exit 1: current, with an optional badge in place of "Up to date".
    case ok(badge: String?)
    /// Exit 3: the subsystem is not set up, or not supported on this Mac.
    case notConfigured
    /// Any other exit, a timeout, or a check that did not start.
    case unavailable

    /// Exit 4: the last update did not complete. It needs the same action as an update.
    static let retry = CheckStatus.needsAttention(badge: "Retry")

    /// Maps an exit code to a state; nil stands for a timeout or a launch failure.
    static func from(exitCode: Int32?) -> CheckStatus {
        switch exitCode {
        case .some(0):
            return .needsAttention(badge: nil)
        case .some(1):
            return .ok(badge: nil)
        case .some(3):
            return .notConfigured
        case .some(4):
            return .retry
        default:
            return .unavailable
        }
    }

    /// Whether the row asks the user to act, which also tints the menu bar icon.
    var needsAction: Bool {
        if case .needsAttention = self {
            return true
        }
        return false
    }

    var isRetry: Bool { self == .retry }
}
