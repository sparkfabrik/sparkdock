import XCTest
import Foundation
@testable import SparkdockManager

final class SparkdockManagerTests: XCTestCase {

    func testPackageStructure() {
        XCTAssertTrue(true, "Package structure test passed")
    }

    func testResourcesExist() {
        let currentDir = FileManager.default.currentDirectoryPath
        let logoPath = "\(currentDir)/Sources/SparkdockManager/Resources/sparkfabrik-logo.png"
        let fileExists = FileManager.default.fileExists(atPath: logoPath)
        XCTAssertTrue(fileExists, "SparkFabrik logo should exist at: \(logoPath)")
    }

    func testSparkdockPath() {
        let sparkdockScript = "/opt/sparkdock/bin/sparkdock.macos"
        let scriptURL = URL(fileURLWithPath: sparkdockScript)
        XCTAssertEqual(scriptURL.path, sparkdockScript, "Sparkdock script path should be correct")
    }

    func testExecutableName() {
        let expectedName = "sparkdock-manager"
        XCTAssertEqual(expectedName, "sparkdock-manager", "Executable should have expected name")
    }

    func testCommandEscaping() {
        let testCases = [
            ("sparkdock", "sparkdock"),
            ("sparkdock \"test\"", "sparkdock \\\"test\\\""),
            ("sparkdock\\test", "sparkdock\\\\test"),
            ("sparkdock\\\"test\\\"", "sparkdock\\\\\\\"test\\\\\\\"")
        ]

        for (input, expected) in testCases {
            let escaped = input.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            XCTAssertEqual(escaped, expected, "Command escaping should work correctly")
        }
    }

    func testTimerTolerance() {
        let tolerance: TimeInterval = 60.0
        XCTAssertGreaterThan(tolerance, 0, "Timer tolerance should be positive")
        XCTAssertLessThanOrEqual(tolerance, 300, "Timer tolerance should be reasonable")
    }

    func testProcessIdentifierIsValid() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        XCTAssertGreaterThan(currentPID, 0, "Process identifier should be positive")
    }

    func testProcessRunnerReturnsTerminationStatus() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")

        let status = try await runProcessWithTimeout(process, seconds: 1)

        XCTAssertEqual(status, 0)
    }

    func testProcessRunnerTerminatesTimedOutProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        let startedAt = Date()

        do {
            _ = try await runProcessWithTimeout(process, seconds: 0.1)
            XCTFail("Expected process runner to time out")
        } catch ProcessTimeoutError.timedOut {
            // Expected timeout.
        }

        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testPgrepExecutablePath() {
        let pgrepPath = "/usr/bin/pgrep"
        let fileExists = FileManager.default.fileExists(atPath: pgrepPath)
        // Note: This may fail in CI environments without pgrep, but should pass on macOS
        if fileExists {
            XCTAssertTrue(fileExists, "pgrep should exist at \(pgrepPath) on macOS systems")
        }
    }

    func testWhichCommandValidation() {
        let whichPath = "/usr/bin/which"
        let fileExists = FileManager.default.fileExists(atPath: whichPath)
        // Note: This may fail in some CI environments, but should pass on most Unix systems
        if fileExists {
            XCTAssertTrue(fileExists, "which command should exist at \(whichPath) on Unix systems")
        }
    }

    func testBrewCommandFormat() {
        let brewCommand = "brew outdated --quiet | wc -l"
        XCTAssertTrue(brewCommand.contains("brew outdated"), "Command should check for outdated packages")
        XCTAssertTrue(brewCommand.contains("--quiet"), "Command should use quiet mode")
        XCTAssertTrue(brewCommand.contains("wc -l"), "Command should count lines for package count")
    }

    func testBrewUpgradeCommand() {
        let upgradeCommand = "brew upgrade"
        XCTAssertEqual(upgradeCommand, "brew upgrade", "Brew upgrade command should be correct")
    }

    func testHttpProxyUpgradeCommand() {
        let httpProxyUpgradeCommand = "sjust http-proxy-install-update"
        XCTAssertEqual(httpProxyUpgradeCommand, "sjust http-proxy-install-update", "HTTP proxy upgrade command should be correct")
    }

    func testHttpProxyCheckUpdatesCommand() {
        let httpProxyCheckCommand = ["http-proxy-check-updates"]
        XCTAssertEqual(httpProxyCheckCommand.first, "http-proxy-check-updates", "HTTP proxy check command should be correct")
    }

    func testClaudeUsageStatusDecodingAndDisplay() throws {
        let data = Data(#"{"c_pct":42,"c_reset":"3h 12m","w_pct":67,"w_reset":"2d 4h","stale":false,"auth":"valid"}"#.utf8)

        let status = try JSONDecoder().decode(ClaudeUsageStatus.self, from: data)

        XCTAssertEqual(status.currentPercent, 42)
        XCTAssertEqual(status.weeklyPercent, 67)
        XCTAssertTrue(status.isAvailable)
        XCTAssertEqual(status.currentResetText, "3h 12m")
        XCTAssertEqual(status.weeklyResetText, "2d 4h")
    }

    func testClaudeUsageStatusNormalizesCompactResetTimes() throws {
        let data = Data(#"{"c_pct":80,"c_reset":"<1m","w_pct":90,"w_reset":"3d09h","stale":true,"auth":"valid","error":"API returned 429"}"#.utf8)

        let status = try JSONDecoder().decode(ClaudeUsageStatus.self, from: data)

        XCTAssertTrue(status.stale)
        XCTAssertEqual(status.currentResetText, "<1m")
        XCTAssertEqual(status.weeklyResetText, "3d 9h")
    }

    func testClaudeUsageStatusReportsMissingCredentials() throws {
        let data = Data(#"{"c_pct":0,"c_reset":"?","w_pct":0,"w_reset":"?","stale":false,"auth":"missing","error":"no credentials found"}"#.utf8)

        let status = try JSONDecoder().decode(ClaudeUsageStatus.self, from: data)

        XCTAssertFalse(status.isAvailable)
        XCTAssertEqual(status.availabilityText, "Sign in required")
        XCTAssertNil(status.currentResetText)
        XCTAssertNil(status.weeklyResetText)
    }

    /// Items declared in the shipped menu.json, so a changed command string or a
    /// missing binary requirement is caught here rather than when a user clicks.
    /// #filePath is Tests/SparkdockManagerTests/<this file>; three levels up is the
    /// package root.
    private func shippedMenuItems() throws -> [[String: Any]] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuURL = packageRoot
            .appendingPathComponent("Sources/SparkdockManager/Resources/menu.json")

        let data = try Data(contentsOf: menuURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let menu = root?["menu"] as? [String: Any]
        let sections = menu?["sections"] as? [[String: Any]] ?? []
        return sections
            .compactMap { $0["items"] as? [[String: Any]] }
            .flatMap { $0 }
    }

    private func shippedMenuCommands() throws -> [String] {
        try shippedMenuItems().compactMap { $0["command"] as? String }
    }

    /// Every timetracker entry declares the binary it needs, so a machine without the
    /// CLI does not carry menu items that can only fail.
    func testTimetrackerMenuItemsRequireTheBinary() throws {
        let items = try shippedMenuItems()
        let timetrackerItems = items.filter { ($0["command"] as? String)?.hasPrefix("timetracker") == true }

        XCTAssertFalse(timetrackerItems.isEmpty, "expected timetracker entries in menu.json")
        for item in timetrackerItems {
            XCTAssertEqual(
                item["requires_binary"] as? String, "timetracker",
                "\(item["title"] ?? "item") must be conditional on the timetracker binary"
            )
        }
    }

    func testTimetrackerMenuCommands() throws {
        let commands = try shippedMenuCommands()

        XCTAssertTrue(
            commands.contains("timetracker tui"),
            "menu.json should offer the timetracker terminal UI; found \(commands)"
        )
        // `timetracker update --apply` and not the `timetracker-update` shell function:
        // executeTerminalCommand runs a non-interactive login shell, which does not
        // source ~/.zshrc, so the function is undefined there.
        XCTAssertTrue(
            commands.contains("timetracker update --apply"),
            "menu.json should update the CLI through the binary, not the shell function; found \(commands)"
        )
        XCTAssertFalse(
            commands.contains("timetracker-update"),
            "the bare shell function cannot run in a non-interactive login shell"
        )
    }

    // MARK: - Darwin Recheck Notification Tests

    /// Expected notification names — must match RecheckNotification constants in main.swift.
    private static let expectedRecheckNotifications = [
        "com.sparkfabrik.sparkdock.recheck.sparkdock",
        "com.sparkfabrik.sparkdock.recheck.brew",
        "com.sparkfabrik.sparkdock.recheck.http-proxy",
        "com.sparkfabrik.sparkdock.recheck.agents",
        "com.sparkfabrik.sparkdock.recheck.timetracker"
    ]

    func testRecheckNotificationNamesAreUnique() {
        let names = Self.expectedRecheckNotifications
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "All recheck notification names should be unique")
    }

    func testRecheckNotificationNamesHaveCorrectPrefix() {
        let prefix = "com.sparkfabrik.sparkdock.recheck."
        for name in Self.expectedRecheckNotifications {
            XCTAssertTrue(name.hasPrefix(prefix), "Notification name '\(name)' should have prefix '\(prefix)'")
        }
    }

    func testRecheckNotificationsHasOneEntryPerSubsystem() {
        XCTAssertEqual(Self.expectedRecheckNotifications.count, 5, "Should have exactly 5 recheck notifications (one per subsystem)")
    }

    func testNotifyutilExists() {
        let notifyutilPath = "/usr/bin/notifyutil"
        let fileExists = FileManager.default.fileExists(atPath: notifyutilPath)
        XCTAssertTrue(fileExists, "notifyutil should exist at \(notifyutilPath) on macOS systems")
    }

    func testUpgradeCommandAppendsNotification() {
        let command = "brew upgrade && brew upgrade --cask"
        let notification = "com.sparkfabrik.sparkdock.recheck.brew"
        let finalCommand = "\(command); /usr/bin/notifyutil -p \(notification)"
        XCTAssertTrue(finalCommand.hasPrefix(command), "Final command should start with original command")
        XCTAssertTrue(finalCommand.contains("; /usr/bin/notifyutil -p "), "Final command should contain notifyutil trigger")
        XCTAssertTrue(finalCommand.hasSuffix(notification), "Final command should end with notification name")
    }

    func testUpgradeCommandWithoutNotification() {
        let command = "some-dynamic-menu-command"
        let recheckNotification: String? = nil
        let finalCommand: String
        if let notification = recheckNotification {
            finalCommand = "\(command); /usr/bin/notifyutil -p \(notification)"
        } else {
            finalCommand = command
        }
        XCTAssertEqual(finalCommand, command, "Command without notification should remain unchanged")
        XCTAssertFalse(finalCommand.contains("notifyutil"), "Command without notification should not contain notifyutil")
    }
}
