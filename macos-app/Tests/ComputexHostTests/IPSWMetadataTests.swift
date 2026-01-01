import XCTest
@testable import ComputexHost

final class IPSWMetadataTests: XCTestCase {
    func testExtractsVersionFromFilename() {
        let url = URL(fileURLWithPath: "/tmp/UniversalMac_15.1_23B68_Restore.ipsw")
        XCTAssertEqual(IPSWMetadata.versionLabel(for: url), "15.1")
    }

    func testExtractsThreePartVersion() {
        let url = URL(fileURLWithPath: "/tmp/macOS_14.2.1_Restore.ipsw")
        XCTAssertEqual(IPSWMetadata.versionLabel(for: url), "14.2.1")
    }

    func testReturnsNilWhenNoVersion() {
        let url = URL(fileURLWithPath: "/tmp/Restore.ipsw")
        XCTAssertNil(IPSWMetadata.versionLabel(for: url))
    }
}
