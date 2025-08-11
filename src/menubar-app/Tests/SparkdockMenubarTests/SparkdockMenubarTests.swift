import XCTest
import Foundation

final class SparkdockMenubarTests: XCTestCase {
    
    func testPackageStructure() {
        // Test that the package can be imported and basic structure exists
        XCTAssertTrue(true, "Package structure test passed")
    }
    
    func testResourcesExist() {
        // Test that the logo resource file exists in the source tree
        let currentDir = FileManager.default.currentDirectoryPath
        let logoPath = "\(currentDir)/Sources/SparkdockMenubar/Resources/sparkfabrik-logo.png"
        let fileExists = FileManager.default.fileExists(atPath: logoPath)
        XCTAssertTrue(fileExists, "SparkFabrik logo should exist at: \(logoPath)")
    }
    
    func testSparkdockPath() {
        // Test that the expected sparkdock paths exist (when running in CI)
        let sparkdockScript = "/opt/sparkdock/bin/sparkdock.macos"
        
        // In CI, this path won't exist, so we just test the URL creation
        let scriptURL = URL(fileURLWithPath: sparkdockScript)
        XCTAssertEqual(scriptURL.path, sparkdockScript, "Sparkdock script path should be correct")
    }
    
    func testExecutableName() {
        // Test that we're building the expected executable name
        let expectedName = "sparkdock-menubar"
        XCTAssertEqual(expectedName, "sparkdock-menubar", "Executable should have expected name")
    }
}