import AppKit
import Foundation
import SwiftUI
import Virtualization

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [VMSessionSummary] = []
    @Published var selectedSessionID: String?
    @Published var status: AppStatus = .idle
    @Published var statusDetail: String?
    @Published var logLines: [String] = []
    @Published var virtualMachine: VZVirtualMachine?
    @Published var needsBaseSetup = false
    @Published var restoreSelection: RestoreImageSelection?
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isInstalling = false
    @Published var installProgress: Double = 0
    @Published var baseInstalled = false
    @Published var baseReady = false
    @Published var hasLatestRestoreImage = false
    @Published var storedIPSWs: [StoredIPSW] = []
    @Published var preferences: VMPrefs = VMPrefs.default()
    @Published var catalogCache = CatalogCache(lastUpdated: nil, lastError: nil, latestLabel: nil)
    @Published var isRefreshingCatalog = false

    private let manager = VMManager()
    private lazy var settingsStore = SettingsStore(url: manager.settingsURL())
    private var settings = AppSettings.default()
    private var activeInstance: VMInstance?
    private var didBootstrap = false

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if Bundle.main.bundleURL.pathExtension != "app" {
            log("Warning: not running from an .app bundle. Virtualization entitlements may be missing. Use scripts/dev-run.sh or scripts/run.sh.")
        }

        settings = settingsStore.load()
        applySettings(settings)

        sessions = await manager.loadSessionSummaries()
        selectedSessionID = sessions.first?.id

        refreshBaseStatus()
        syncLatestRestoreImageEntry()
        hasLatestRestoreImage = manager.hasRestoreImage()
    }

    func startPrimarySession() async {
        await startSession(kind: .primary)
    }

    func startDisposableSession() async {
        await startSession(kind: .disposable)
    }

    func stopSession() async {
        guard let instance = activeInstance else { return }
        status = .stopping
        statusDetail = nil
        do {
            let mode = instance.mode
            try await instance.stop()
            if case .session(.disposable) = mode {
                try? manager.deleteSession(id: instance.id)
                sessions = await manager.loadSessionSummaries()
            }
            activeInstance = nil
            virtualMachine = nil
            needsBaseSetup = false
            status = .stopped
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to stop VM: \(error.localizedDescription)")
        }
    }

    func downloadLatestRestoreImage() async {
        status = .downloading
        statusDetail = "Downloading latest restore image"
        isDownloading = true
        downloadProgress = 0
        log("Starting restore image download (latest supported).")
        do {
            try await manager.downloadLatestRestoreImage { [weak self] fraction in
                Task { @MainActor in
                    self?.downloadProgress = fraction
                }
            }
            upsertLatestRestoreImageEntry()
            selectStoredIPSW(id: "latest")
            status = .idle
            statusDetail = nil
            log("Restore image downloaded.")
            hasLatestRestoreImage = true
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Restore image download failed: \(error.localizedDescription)")
            if error.localizedDescription.localizedCaseInsensitiveContains("restore image catalog failed to load") {
                log("Hint: swift run does not apply the virtualization entitlement. Use scripts/dev-run.sh for debugging.")
            }
        }
        isDownloading = false
    }

    func importIPSW(url: URL) {
        do {
            let stored = try copyIPSWToLibrary(url)
            storedIPSWs.append(stored)
            storedIPSWs.sort { $0.downloadedAt > $1.downloadedAt }
            settings.ipsws = storedIPSWs
            selectStoredIPSW(id: stored.id)
            persistSettings()
            log("Imported IPSW: \(stored.fileName)")
        } catch {
            reportError(error)
        }
    }

    func selectStoredIPSW(id: String) {
        guard let entry = storedIPSWs.first(where: { $0.id == id }) else { return }
        let label = entry.versionLabel ?? entry.fileName
        restoreSelection = RestoreImageSelection(url: entry.url, source: entry.source, label: label, storedID: entry.id)
        settings.selectedIPSWID = entry.id
        persistSettings()
        log("Selected IPSW: \(entry.fileName)")
    }

    func deleteStoredIPSW(id: String) {
        guard let entry = storedIPSWs.first(where: { $0.id == id }) else { return }
        do {
            if id == "latest" {
                if FileManager.default.fileExists(atPath: manager.restoreImageURL().path) {
                    try FileManager.default.removeItem(at: manager.restoreImageURL())
                }
            } else if FileManager.default.fileExists(atPath: entry.localPath) {
                try FileManager.default.removeItem(atPath: entry.localPath)
            }
            storedIPSWs.removeAll { $0.id == id }
            settings.ipsws = storedIPSWs
            if settings.selectedIPSWID == id {
                settings.selectedIPSWID = nil
                restoreSelection = nil
            }
            persistSettings()
            refreshBaseStatus()
            log("Deleted IPSW: \(entry.fileName)")
        } catch {
            reportError(error)
        }
    }

    func installBaseFromSelection() async {
        guard let selection = restoreSelection else { return }
        status = .installing
        statusDetail = "Installing base VM"
        isInstalling = true
        installProgress = 0
        log("Starting base VM install from \(selection.url.lastPathComponent).")
        do {
            try await manager.installBase(restoreImageURL: selection.url) { [weak self] fraction in
                Task { @MainActor in
                    self?.installProgress = fraction
                }
            }
            refreshBaseStatus()
            status = .idle
            statusDetail = nil
            log("Base VM installed.")
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Base VM install failed: \(error.localizedDescription)")
        }
        isInstalling = false
    }

    func resetBaseVM() {
        do {
            try manager.deleteBase()
            refreshBaseStatus()
            log("Base VM deleted.")
        } catch {
            reportError(error)
        }
    }

    func startBaseSetup() async {
        status = .starting
        statusDetail = "Starting base VM for setup"
        log("Starting base VM for setup.")
        do {
            let instance = try await manager.startBaseSetup()
            activeInstance = instance
            virtualMachine = instance.virtualMachine
            needsBaseSetup = true
            status = .running
            statusDetail = nil
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to start base VM: \(error.localizedDescription)")
        }
    }

    func markBaseReady() async {
        do {
            try manager.markBaseReady()
            needsBaseSetup = false
            refreshBaseStatus()
            log("Base VM marked ready. Future sessions will clone from it.")
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to mark base ready: \(error.localizedDescription)")
        }
    }

    func refreshCatalog() async {
        isRefreshingCatalog = true
        let result = await manager.refreshRestoreImageCatalog()
        switch result {
        case .success:
            catalogCache.lastUpdated = Date()
            catalogCache.lastError = nil
            catalogCache.latestLabel = "Latest Supported"
            log("Restore image catalog refreshed.")
        case .failure(let error):
            catalogCache.lastError = error.localizedDescription
            log("Restore image catalog refresh failed: \(error.localizedDescription)")
        }
        settings.catalog = catalogCache
        persistSettings()
        isRefreshingCatalog = false
    }

    func updatePreferences(cpuCount: Int? = nil, memoryGB: Int? = nil, diskGB: Int? = nil) {
        var updated = preferences
        if let cpuCount {
            updated.cpuCount = max(1, cpuCount)
            log("Updated CPU preference: \(updated.cpuCount) cores")
        }
        if let memoryGB {
            updated.memoryGB = max(2, memoryGB)
            log("Updated Memory preference: \(updated.memoryGB) GB")
        }
        if let diskGB {
            updated.diskGB = max(32, diskGB)
            log("Updated Disk preference: \(updated.diskGB) GB")
        }
        preferences = updated
        settings.preferences = updated
        manager.updateSizing(VMResourceSizing.fromPreferences(updated))
        persistSettings()
    }

    func openIPSWFolder() {
        NSWorkspace.shared.open(manager.ipswDirectoryURL())
    }

    private func startSession(kind: SessionKind) async {
        status = .preparing
        statusDetail = nil
        log("Preparing \(kind.label) session")

        do {
            let instance = try await manager.startSession(kind: kind) { [weak self] message in
                Task { @MainActor in
                    self?.log(message)
                }
            } progress: { [weak self] detail in
                Task { @MainActor in
                    self?.statusDetail = detail
                    let normalized = detail.lowercased()
                    if normalized.contains("download") {
                        self?.status = .downloading
                    } else if normalized.contains("install") {
                        self?.status = .installing
                    } else if normalized.contains("start") {
                        self?.status = .starting
                    } else {
                        self?.status = .preparing
                    }
                }
            }
            activeInstance = instance
            virtualMachine = instance.virtualMachine
            needsBaseSetup = instance.mode == .baseSetup
            status = .running
            statusDetail = nil
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to start VM: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        AppLog.writeLine(line)
        logLines.append(line)
    }

    private func refreshBaseStatus() {
        baseInstalled = manager.baseExists()
        baseReady = manager.isBaseReady(manager.baseArtifacts())
        hasLatestRestoreImage = manager.hasRestoreImage()
    }

    private func applySettings(_ settings: AppSettings) {
        storedIPSWs = settings.ipsws
        preferences = settings.preferences
        catalogCache = settings.catalog
        manager.updateSizing(VMResourceSizing.fromPreferences(preferences))

        if let selectedID = settings.selectedIPSWID, storedIPSWs.contains(where: { $0.id == selectedID }) {
            selectStoredIPSW(id: selectedID)
        } else if manager.hasRestoreImage() {
            upsertLatestRestoreImageEntry()
            selectStoredIPSW(id: "latest")
        }
    }

    private func persistSettings() {
        settings.ipsws = storedIPSWs
        settings.preferences = preferences
        settings.catalog = catalogCache
        settingsStore.save(settings)
    }

    private func syncLatestRestoreImageEntry() {
        guard manager.hasRestoreImage() else {
            storedIPSWs.removeAll { $0.id == "latest" }
            settings.ipsws = storedIPSWs
            persistSettings()
            return
        }
        upsertLatestRestoreImageEntry()
    }

    private func upsertLatestRestoreImageEntry() {
        let latestID = "latest"
        let url = manager.restoreImageURL()
        let label = IPSWMetadata.versionLabel(for: url) ?? catalogCache.latestLabel ?? "Latest Supported"
        let fileName = url.lastPathComponent
        let entry = StoredIPSW(
            id: latestID,
            fileName: fileName,
            localPath: url.path,
            versionLabel: label,
            source: .latest,
            downloadedAt: Date()
        )

        if let index = storedIPSWs.firstIndex(where: { $0.id == latestID }) {
            storedIPSWs[index] = entry
        } else {
            storedIPSWs.insert(entry, at: 0)
        }
        settings.ipsws = storedIPSWs
        persistSettings()
    }

    private func copyIPSWToLibrary(_ url: URL) throws -> StoredIPSW {
        try FileManager.default.createDirectory(at: manager.ipswDirectoryURL(), withIntermediateDirectories: true)
        let fileName = url.lastPathComponent
        let destName = "\(UUID().uuidString.lowercased())-\(fileName)"
        let destination = manager.ipswDirectoryURL().appendingPathComponent(destName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        let label = IPSWMetadata.versionLabel(for: destination) ?? IPSWMetadata.versionLabel(for: url) ?? fileName
        return StoredIPSW(
            id: UUID().uuidString.lowercased(),
            fileName: fileName,
            localPath: destination.path,
            versionLabel: label,
            source: .manual,
            downloadedAt: Date()
        )
    }

    func reportError(_ error: Error) {
        status = .error
        statusDetail = error.localizedDescription
        log("Error: \(error.localizedDescription)")
    }
}

enum AppStatus: String {
    case idle
    case preparing
    case downloading
    case installing
    case starting
    case running
    case stopping
    case stopped
    case error

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing VM"
        case .downloading:
            return "Downloading IPSW"
        case .installing:
            return "Installing macOS"
        case .starting:
            return "Starting VM"
        case .running:
            return "Running"
        case .stopping:
            return "Stopping"
        case .stopped:
            return "Stopped"
        case .error:
            return "Error"
        }
    }
}
