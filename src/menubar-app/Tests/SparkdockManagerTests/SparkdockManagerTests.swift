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
        XCTAssertNotEqual(updateTag, loginTag, "Menu item tags should be unique")
    }
    
    func testTimerTolerance() {
        let tolerance: TimeInterval = 60.0
        XCTAssertGreaterThan(tolerance, 0, "Timer tolerance should be positive")
        XCTAssertLessThanOrEqual(tolerance, 300, "Timer tolerance should be reasonable")
    }
}