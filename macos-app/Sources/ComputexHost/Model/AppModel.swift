import AppKit
import Foundation
import SwiftUI
import Virtualization

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [VMSessionSummary] = []
    @Published var selectedSessionID: String?
    @Published var activeSessionID: String?
    @Published var checkpoints: [VMCheckpoint] = []
    @Published var selectedCheckpointID: String?
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
    @Published var credentials: VMCredentials = VMCredentials.default()
    @Published var catalogCache = CatalogCache(lastUpdated: nil, lastError: nil, latestLabel: nil)
    @Published var isRefreshingCatalog = false
    @Published var isSavingCheckpoint = false

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
        refreshCheckpoints()

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
        await stopActiveInstance(deleteDisposable: true)
    }

    func selectSession(id: String) {
        selectedSessionID = id
        refreshCheckpoints()
    }

    func refreshCheckpoints() {
        guard let sessionID = selectedSessionID else {
            checkpoints = []
            selectedCheckpointID = nil
            return
        }
        checkpoints = manager.loadCheckpoints(sessionID: sessionID)
        if let first = checkpoints.first {
            selectedCheckpointID = first.id
        } else {
            selectedCheckpointID = nil
        }
    }

    func startSelectedSession() async {
        guard let sessionID = selectedSessionID,
              let summary = sessions.first(where: { $0.id == sessionID }) else {
            log("Select a session first.")
            return
        }
        guard baseReady else {
            log("Base VM is not ready.")
            return
        }
        status = .starting
        statusDetail = "Starting \(summary.name)"
        do {
            let instance = try await manager.buildSessionInstance(sessionID, kind: summary.kind)
            activeInstance = instance
            virtualMachine = instance.virtualMachine
            activeSessionID = instance.id
            needsBaseSetup = false
            try await instance.start()
            status = .running
            statusDetail = nil
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to start session: \(error.localizedDescription)")
        }
    }

    func saveCheckpoint(name: String) async {
        guard let instance = activeInstance else {
            log("No running VM to checkpoint.")
            return
        }
        guard case .session = instance.mode else {
            log("Checkpoints are only available for session VMs.")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkpointName = trimmedName.isEmpty ? defaultCheckpointName() : trimmedName
        let sessionID = instance.id
        let checkpointID = UUID().uuidString.lowercased()
        let checkpoint = VMCheckpoint(
            id: checkpointID,
            sessionID: sessionID,
            name: checkpointName,
            createdAt: Date(),
            hasState: true
        )
        let paths = manager.checkpointPaths(sessionID: sessionID, checkpointID: checkpointID)

        selectedSessionID = sessionID
        isSavingCheckpoint = true
        status = .preparing
        statusDetail = "Saving checkpoint"
        log("Saving checkpoint '\(checkpointName)' for session \(sessionID).")

        var didPause = false
        do {
            try FileManager.default.createDirectory(at: paths.bundle, withIntermediateDirectories: true)
            try await instance.pause()
            didPause = true
            try await instance.saveState(to: paths.state)

            let artifacts = manager.sessionArtifacts(id: sessionID)
            try manager.cloneDiskImage(from: artifacts.diskImageURL, to: paths.disk)
            try manager.writeCheckpointMetadata(checkpoint)

            try await instance.resume()
            didPause = false

            status = .running
            statusDetail = nil
            isSavingCheckpoint = false
            refreshCheckpoints()
            log("Checkpoint saved: \(checkpointName)")
        } catch {
            if didPause {
                try? await instance.resume()
            }
            status = .error
            statusDetail = error.localizedDescription
            isSavingCheckpoint = false
            log("Failed to save checkpoint: \(error.localizedDescription)")
        }
    }

    func saveDiskCheckpoint(name: String) async {
        guard let sessionID = selectedSessionID else {
            log("Select a session first.")
            return
        }
        if activeSessionID == sessionID {
            log("Stop the VM or use Save Checkpoint for a running session.")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkpointName = trimmedName.isEmpty ? defaultCheckpointName() : trimmedName
        let checkpointID = UUID().uuidString.lowercased()
        let checkpoint = VMCheckpoint(
            id: checkpointID,
            sessionID: sessionID,
            name: checkpointName,
            createdAt: Date(),
            hasState: false
        )
        let paths = manager.checkpointPaths(sessionID: sessionID, checkpointID: checkpointID)
        let artifacts = manager.sessionArtifacts(id: sessionID)
        if !artifacts.exists() {
            log("Session artifacts missing for \(sessionID).")
            return
        }

        status = .preparing
        statusDetail = "Saving disk checkpoint"
        log("Saving disk-only checkpoint '\(checkpointName)' for session \(sessionID).")
        do {
            try FileManager.default.createDirectory(at: paths.bundle, withIntermediateDirectories: true)
            try manager.cloneDiskImage(from: artifacts.diskImageURL, to: paths.disk)
            try manager.writeCheckpointMetadata(checkpoint)
            status = .idle
            statusDetail = nil
            refreshCheckpoints()
            log("Disk checkpoint saved: \(checkpointName)")
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to save disk checkpoint: \(error.localizedDescription)")
        }
    }

    func restoreCheckpoint(id: String) async {
        guard let checkpoint = checkpoints.first(where: { $0.id == id }) else {
            log("Checkpoint not found.")
            return
        }
        guard let summary = sessions.first(where: { $0.id == checkpoint.sessionID }) else {
            log("Session not found for checkpoint.")
            return
        }

        status = .starting
        statusDetail = "Restoring checkpoint"
        log("Restoring checkpoint '\(checkpoint.name)'.")

        do {
            if activeInstance != nil {
                await stopActiveInstance(deleteDisposable: false)
            }

            let artifacts = manager.sessionArtifacts(id: checkpoint.sessionID)
            let paths = manager.checkpointPaths(sessionID: checkpoint.sessionID, checkpointID: checkpoint.id)

            if !FileManager.default.fileExists(atPath: paths.disk.path) ||
                !FileManager.default.fileExists(atPath: paths.state.path) {
                throw VMError.checkpointNotFound(checkpoint.id)
            }

            try manager.cloneDiskImage(from: paths.disk, to: artifacts.diskImageURL)
            let instance = try await manager.buildSessionInstance(checkpoint.sessionID, kind: summary.kind)

            activeInstance = instance
            virtualMachine = instance.virtualMachine
            activeSessionID = instance.id
            selectedSessionID = checkpoint.sessionID

            if checkpoint.hasState && FileManager.default.fileExists(atPath: paths.state.path) {
                try await instance.restoreState(from: paths.state)
                try await instance.resume()
            } else {
                try await instance.start()
            }

            status = .running
            statusDetail = nil
            refreshCheckpoints()
            log("Checkpoint restored: \(checkpoint.name)")
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to restore checkpoint: \(error.localizedDescription)")
        }
    }

    func deleteCheckpoint(id: String) {
        guard let checkpoint = checkpoints.first(where: { $0.id == id }) else { return }
        do {
            try manager.deleteCheckpoint(sessionID: checkpoint.sessionID, checkpointID: checkpoint.id)
            refreshCheckpoints()
            log("Deleted checkpoint: \(checkpoint.name)")
        } catch {
            reportError(error)
        }
    }

    func deleteSession(id: String) async {
        if activeSessionID == id {
            log("Stop the running VM before deleting its session.")
            return
        }
        do {
            try manager.deleteSession(id: id)
            sessions = await manager.loadSessionSummaries()
            if selectedSessionID == id {
                selectedSessionID = sessions.first?.id
            }
            refreshCheckpoints()
            log("Deleted session: \(id)")
        } catch {
            reportError(error)
        }
    }

    func createPrimaryFromBase() async {
        if activeSessionID == "primary" {
            log("Stop the running primary VM before resetting it.")
            return
        }
        guard baseReady else {
            log("Base VM is not ready.")
            return
        }
        do {
            try manager.deleteSession(id: "primary")
        } catch {
            log("Failed to delete primary: \(error.localizedDescription)")
        }

        do {
            try manager.createPrimaryFromBase()
            sessions = await manager.loadSessionSummaries()
            selectedSessionID = "primary"
            refreshCheckpoints()
            log("Primary session recreated from base.")
        } catch {
            reportError(error)
        }
    }

    func cloneSession(name: String, source: SessionCloneSource) async {
        do {
            if source == .base && !baseReady {
                log("Base VM is not ready.")
                return
            }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? defaultSessionName(source: source) : trimmedName
            let summary = try manager.cloneSession(name: finalName, source: source, selectedSessionID: selectedSessionID)
            sessions = await manager.loadSessionSummaries()
            selectedSessionID = summary.id
            refreshCheckpoints()
            log("Session cloned: \(summary.name)")
        } catch {
            reportError(error)
        }
    }

    func openCheckpointsFolder() {
        guard let sessionID = selectedSessionID else { return }
        manager.openCheckpointsFolder(sessionID: sessionID)
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
            let instance = try await manager.buildBaseSetupInstance()
            activeInstance = instance
            virtualMachine = instance.virtualMachine
            activeSessionID = nil
            needsBaseSetup = true
            try await instance.start()
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
            log("Restore image catalog refresh failed: \(error.localizedDescription) (\(ErrorDiagnostics.describe(error)))")
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

    func updateCredentials(username: String? = nil, password: String? = nil) {
        var updated = credentials
        if let username {
            updated.username = username
            log("Updated VM username.")
        }
        if let password {
            updated.password = password
            log("Updated VM password.")
        }
        credentials = updated
        settings.credentials = updated
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
            let instance = try await manager.prepareSessionInstance(kind: kind) { [weak self] message in
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
            activeSessionID = instance.id
            try await instance.start()
            status = .running
            statusDetail = nil
            sessions = await manager.loadSessionSummaries()
            selectedSessionID = instance.id
            refreshCheckpoints()
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

    private func stopActiveInstance(deleteDisposable: Bool) async {
        guard let instance = activeInstance else { return }
        status = .stopping
        statusDetail = nil
        do {
            let mode = instance.mode
            try await instance.stop()
            if deleteDisposable, case .session(.disposable) = mode {
                try? manager.deleteSession(id: instance.id)
                sessions = await manager.loadSessionSummaries()
                if selectedSessionID == instance.id {
                    selectedSessionID = sessions.first?.id
                }
            }
            activeInstance = nil
            virtualMachine = nil
            activeSessionID = nil
            needsBaseSetup = false
            status = .stopped
            refreshCheckpoints()
        } catch {
            status = .error
            statusDetail = error.localizedDescription
            log("Failed to stop VM: \(error.localizedDescription)")
        }
    }

    private func defaultCheckpointName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Checkpoint \(formatter.string(from: Date()))"
    }

    private func defaultSessionName(source: SessionCloneSource) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let sourceLabel: String
        switch source {
        case .base:
            sourceLabel = "Base"
        case .primary:
            sourceLabel = "Primary"
        case .selected:
            sourceLabel = "Session"
        }
        return "\(sourceLabel) Clone \(formatter.string(from: Date()))"
    }

    private func refreshBaseStatus() {
        baseInstalled = manager.baseExists()
        baseReady = manager.isBaseReady(manager.baseArtifacts())
        hasLatestRestoreImage = manager.hasRestoreImage()
    }

    private func applySettings(_ settings: AppSettings) {
        storedIPSWs = settings.ipsws
        preferences = settings.preferences
        credentials = settings.credentials
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
        settings.credentials = credentials
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
