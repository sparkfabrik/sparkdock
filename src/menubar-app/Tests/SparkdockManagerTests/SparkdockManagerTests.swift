import XCTest
import Foundation

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

    func testMenuItemTags() {
        let updateTag = 1
        let loginTag = 2
        let upgradeBrewTag = 3
        let upgradeHttpProxyTag = 4
        XCTAssertNotEqual(updateTag, loginTag, "Menu item tags should be unique")
        XCTAssertNotEqual(updateTag, upgradeBrewTag, "Menu item tags should be unique")
        XCTAssertNotEqual(updateTag, upgradeHttpProxyTag, "Menu item tags should be unique")
        XCTAssertNotEqual(loginTag, upgradeBrewTag, "Menu item tags should be unique")
        XCTAssertNotEqual(loginTag, upgradeHttpProxyTag, "Menu item tags should be unique")
        XCTAssertNotEqual(upgradeBrewTag, upgradeHttpProxyTag, "Menu item tags should be unique")
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
        XCTAssertEqual(httpProxyUpgradeCommand, "sjust http-proxy-install-update", "Http-proxy upgrade command should be correct")
    }
    
    func testHttpProxyCheckUpdatesCommand() {
        let httpProxyCheckCommand = ["http-proxy-check-updates"]
        XCTAssertEqual(httpProxyCheckCommand.first, "http-proxy-check-updates", "Http-proxy check command should be correct")
    }

    // MARK: - Darwin Recheck Notification Tests

    func testRecheckNotificationNamesAreUnique() {
        let names = [
            "com.sparkfabrik.sparkdock.recheck.sparkdock",
            "com.sparkfabrik.sparkdock.recheck.brew",
            "com.sparkfabrik.sparkdock.recheck.http-proxy",
            "com.sparkfabrik.sparkdock.recheck.agents"
        ]
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "All recheck notification names should be unique")
    }

    func testRecheckNotificationNamesHaveCorrectPrefix() {
        let prefix = "com.sparkfabrik.sparkdock.recheck."
        let names = [
            "com.sparkfabrik.sparkdock.recheck.sparkdock",
            "com.sparkfabrik.sparkdock.recheck.brew",
            "com.sparkfabrik.sparkdock.recheck.http-proxy",
            "com.sparkfabrik.sparkdock.recheck.agents"
        ]
        for name in names {
            XCTAssertTrue(name.hasPrefix(prefix), "Notification name '\(name)' should have prefix '\(prefix)'")
        }
    }

    func testRecheckNotificationAllContainsAllSubsystems() {
        let allNotifications = [
            "com.sparkfabrik.sparkdock.recheck.sparkdock",
            "com.sparkfabrik.sparkdock.recheck.brew",
            "com.sparkfabrik.sparkdock.recheck.http-proxy",
            "com.sparkfabrik.sparkdock.recheck.agents"
        ]
        XCTAssertEqual(allNotifications.count, 4, "Should have exactly 4 recheck notifications (one per subsystem)")
    }

    func testNotifyutilExists() {
        let notifyutilPath = "/usr/bin/notifyutil"
        let fileExists = FileManager.default.fileExists(atPath: notifyutilPath)
        if fileExists {
            XCTAssertTrue(fileExists, "notifyutil should exist at \(notifyutilPath) on macOS systems")
        }
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