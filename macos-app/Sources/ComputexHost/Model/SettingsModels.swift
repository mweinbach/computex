import Foundation

struct StoredIPSW: Identifiable, Codable, Equatable {
    let id: String
    let fileName: String
    let localPath: String
    let versionLabel: String?
    let source: RestoreImageSource
    let downloadedAt: Date

    var url: URL {
        URL(fileURLWithPath: localPath)
    }
}

struct VMPrefs: Codable, Equatable {
    var cpuCount: Int
    var memoryGB: Int
    var diskGB: Int

    static func `default`() -> VMPrefs {
        VMPrefs(cpuCount: 2, memoryGB: 4, diskGB: 64)
    }
}

struct CatalogCache: Codable, Equatable {
    var lastUpdated: Date?
    var lastError: String?
    var latestLabel: String?
}

struct AppSettings: Codable, Equatable {
    var selectedIPSWID: String?
    var ipsws: [StoredIPSW]
    var preferences: VMPrefs
    var catalog: CatalogCache

    static func `default`() -> AppSettings {
        AppSettings(
            selectedIPSWID: nil,
            ipsws: [],
            preferences: VMPrefs.default(),
            catalog: CatalogCache(lastUpdated: nil, lastError: nil, latestLabel: nil)
        )
    }
}
