import Foundation
import XCTest
@testable import ComputexHost

final class SettingsStoreTests: XCTestCase {
    func testSettingsRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let settingsURL = tempDir.appendingPathComponent("Settings.json")
        let store = SettingsStore(url: settingsURL)

        let settings = AppSettings(
            selectedIPSWID: "latest",
            ipsws: [StoredIPSW(
                id: "latest",
                fileName: "RestoreImage.ipsw",
                localPath: "/tmp/RestoreImage.ipsw",
                versionLabel: "Latest",
                source: .latest,
                downloadedAt: Date()
            )],
            preferences: VMPrefs(cpuCount: 4, memoryGB: 8, diskGB: 80),
            credentials: VMCredentials(username: "tester", password: "secret"),
            catalog: CatalogCache(lastUpdated: Date(), lastError: nil, latestLabel: "Latest")
        )

        store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
    }
}
