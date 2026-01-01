import Foundation

final class SettingsStore {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            AppLog.info("Settings load failed, using defaults: \(error.localizedDescription)")
            return AppSettings.default()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.error("Failed to save settings: \(error.localizedDescription)")
        }
    }
}
