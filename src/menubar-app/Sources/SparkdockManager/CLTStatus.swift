import Foundation

/// Result of check_clt_health: exit 0 healthy, exit 1 with a diagnosis.
enum CLTStatus: Equatable {
    case unavailable
    case healthy
    case inconsistent(String)

    static func from(exitCode: Int32?, output: String) -> CLTStatus {
        switch exitCode {
        case .some(0):
            return .healthy
        case .some(1):
            let diagnosis = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .inconsistent(diagnosis.isEmpty ? "Command Line Tools are inconsistent." : diagnosis)
        default:
            return .unavailable
        }
    }
}
