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

struct VMCredentials: Codable, Equatable {
    var username: String
    var password: String

    static func `default`() -> VMCredentials {
        VMCredentials(username: "", password: "")
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
    var credentials: VMCredentials
    var catalog: CatalogCache

    static func `default`() -> AppSettings {
        AppSettings(
            selectedIPSWID: nil,
            ipsws: [],
            preferences: VMPrefs.default(),
            credentials: VMCredentials.default(),
            catalog: CatalogCache(lastUpdated: nil, lastError: nil, latestLabel: nil)
        )
    }

    init(
        selectedIPSWID: String?,
        ipsws: [StoredIPSW],
        preferences: VMPrefs,
        credentials: VMCredentials,
        catalog: CatalogCache
    ) {
        self.selectedIPSWID = selectedIPSWID
        self.ipsws = ipsws
        self.preferences = preferences
        self.credentials = credentials
        self.catalog = catalog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedIPSWID = try container.decodeIfPresent(String.self, forKey: .selectedIPSWID)
        ipsws = try container.decodeIfPresent([StoredIPSW].self, forKey: .ipsws) ?? []
        preferences = try container.decodeIfPresent(VMPrefs.self, forKey: .preferences) ?? VMPrefs.default()
        credentials = try container.decodeIfPresent(VMCredentials.self, forKey: .credentials) ?? VMCredentials.default()
        catalog = try container.decodeIfPresent(CatalogCache.self, forKey: .catalog)
            ?? CatalogCache(lastUpdated: nil, lastError: nil, latestLabel: nil)
    }

    private enum CodingKeys: String, CodingKey {
        case selectedIPSWID
        case ipsws
        case preferences
        case credentials
        case catalog
    }
}
