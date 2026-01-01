import Foundation
import XCTest
@testable import ComputexHost

final class VMArtifactsTests: XCTestCase {
    func testArtifactsPaths() {
        let baseURL = URL(fileURLWithPath: "/tmp/Example.vm", isDirectory: true)
        let artifacts = VMArtifacts(bundleURL: baseURL)

        XCTAssertEqual(artifacts.diskImageURL.lastPathComponent, "Disk.img")
        XCTAssertEqual(artifacts.auxiliaryStorageURL.lastPathComponent, "AuxiliaryStorage")
        XCTAssertEqual(artifacts.hardwareModelURL.lastPathComponent, "HardwareModel")
        XCTAssertEqual(artifacts.machineIdentifierURL.lastPathComponent, "MachineIdentifier")
        XCTAssertEqual(artifacts.metadataURL.lastPathComponent, "Session.json")
        XCTAssertEqual(artifacts.baseReadyURL.lastPathComponent, "BaseReady")
    }
}
