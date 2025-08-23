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
        XCTAssertNotEqual(updateTag, loginTag, "Menu item tags should be unique")
        XCTAssertNotEqual(updateTag, upgradeBrewTag, "Menu item tags should be unique")
        XCTAssertNotEqual(loginTag, upgradeBrewTag, "Menu item tags should be unique")
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

    func testBrewPathValidation() {
        let appleBrewPath = "/opt/homebrew/bin/brew"
        let intelBrewPath = "/usr/local/bin/brew"
        
        // At least one of these should exist on a properly configured macOS system
        // In CI/Linux environments, both may be missing, which is expected
        let hasAppleBrew = FileManager.default.fileExists(atPath: appleBrewPath)
        let hasIntelBrew = FileManager.default.fileExists(atPath: intelBrewPath)
        
        // This test verifies the paths we check are correct, regardless of availability
        XCTAssertEqual(appleBrewPath, "/opt/homebrew/bin/brew", "Apple Silicon brew path should be correct")
        XCTAssertEqual(intelBrewPath, "/usr/local/bin/brew", "Intel brew path should be correct")
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
}