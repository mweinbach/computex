import XCTest
@testable import ComputexHost

final class VMPathsTests: XCTestCase {
    func testDefaultRootStructure() {
        let paths = VMPaths.defaultRoot()
        XCTAssertEqual(paths.root.lastPathComponent, "VMs")
        XCTAssertEqual(paths.root.deletingLastPathComponent().lastPathComponent, "Computex")
    }

    func testSessionBundleURL() {
        let paths = VMPaths(root: URL(fileURLWithPath: "/tmp/Computex/VMs"))
        let sessionURL = paths.sessionBundleURL(id: "session-123")
        XCTAssertEqual(sessionURL.lastPathComponent, "session-123.vm")
    }

    func testSettingsAndIPSWPaths() {
        let paths = VMPaths(root: URL(fileURLWithPath: "/tmp/Computex/VMs"))
        XCTAssertEqual(paths.settingsURL.lastPathComponent, "Settings.json")
        XCTAssertEqual(paths.ipswDirectoryURL.lastPathComponent, "IPSWs")
    }
}
