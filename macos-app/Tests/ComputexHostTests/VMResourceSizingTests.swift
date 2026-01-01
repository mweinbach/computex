import Virtualization
import XCTest
@testable import ComputexHost

final class VMResourceSizingTests: XCTestCase {
    func testDefaultSizingWithinBounds() {
        let sizing = VMResourceSizing.default()
        XCTAssertGreaterThanOrEqual(sizing.cpuCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        XCTAssertLessThanOrEqual(sizing.cpuCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        XCTAssertGreaterThanOrEqual(sizing.memorySize, VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        XCTAssertLessThanOrEqual(sizing.memorySize, VZVirtualMachineConfiguration.maximumAllowedMemorySize)
        XCTAssertEqual(sizing.diskSizeGB, 64)
    }

    func testDefaultSizingClampsValues() {
        let sizing = VMResourceSizing.default()
        let expectedCpu = max(
            VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            min(VZVirtualMachineConfiguration.maximumAllowedCPUCount, 2)
        )
        let expectedMemory = max(
            VZVirtualMachineConfiguration.minimumAllowedMemorySize,
            min(VZVirtualMachineConfiguration.maximumAllowedMemorySize, 4 * 1024 * 1024 * 1024)
        )
        XCTAssertEqual(sizing.cpuCount, expectedCpu)
        XCTAssertEqual(sizing.memorySize, expectedMemory)
    }

    func testSizingFromPreferencesClampsDisk() {
        let prefs = VMPrefs(cpuCount: 1, memoryGB: 2, diskGB: 4)
        let sizing = VMResourceSizing.fromPreferences(prefs)
        XCTAssertGreaterThanOrEqual(sizing.diskSizeGB, 32)
    }
}
