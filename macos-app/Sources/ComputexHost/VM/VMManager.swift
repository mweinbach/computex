import AppKit
import CoreGraphics
import Darwin
import Foundation
import Virtualization

@MainActor
final class VMManager {
    private let paths: VMPaths
    private var sizing: VMResourceSizing
    private let displaySize: CGSize
    private let downloader = RestoreImageDownloader()

    init(paths: VMPaths = VMPaths.defaultRoot(), sizing: VMResourceSizing = .default()) {
        self.paths = paths
        self.sizing = sizing
        self.displaySize = CGSize(width: 1280, height: 720)
    }

    func updateSizing(_ sizing: VMResourceSizing) {
        self.sizing = sizing
    }

    func restoreImageURL() -> URL {
        paths.restoreImageURL
    }

    func ipswDirectoryURL() -> URL {
        paths.ipswDirectoryURL
    }

    func settingsURL() -> URL {
        paths.settingsURL
    }

    func hasRestoreImage() -> Bool {
        FileManager.default.fileExists(atPath: paths.restoreImageURL.path)
    }

    func baseArtifacts() -> VMArtifacts {
        VMArtifacts(bundleURL: paths.baseBundleURL)
    }

    func baseExists() -> Bool {
        baseArtifacts().exists()
    }

    func sessionArtifacts(id: String) -> VMArtifacts {
        VMArtifacts(bundleURL: paths.sessionBundleURL(id: id))
    }

    func downloadLatestRestoreImage(progress: @escaping (Double) -> Void) async throws {
        try paths.ensureDirectories()
        AppLog.info("Ensured VM directories at \(paths.root.path).")
        try await downloader.downloadLatestIfNeeded(to: paths.restoreImageURL, progress: progress)
    }

    func installBase(restoreImageURL: URL, progress: @escaping (Double) -> Void) async throws {
        try paths.ensureDirectories()
        let base = baseArtifacts()
        if base.exists() {
            AppLog.info("Base VM already exists at \(base.bundleURL.path).")
            return
        }
        AppLog.info("Installing base VM with \(sizing.cpuCount) CPUs, \(sizing.memorySize / 1024 / 1024 / 1024)GB RAM, \(sizing.diskSizeGB)GB Disk.")
        let installer = VMInstaller(sizing: sizing, displaySize: displaySize)
        AppLog.info("Installing base VM at \(base.bundleURL.path).")
        try await installer.installBase(restoreImageURL: restoreImageURL, artifacts: base, diskSizeGB: UInt64(sizing.diskSizeGB), progress: progress)
    }

    func buildBaseSetupInstance() async throws -> VMInstance {
        try paths.ensureDirectories()
        let base = baseArtifacts()
        guard base.exists() else {
            AppLog.error("Base VM not found at \(base.bundleURL.path).")
            throw VMError.baseNotReady
        }
        AppLog.info("Starting base setup VM.")
        return try await buildInstance(sessionID: "base-setup", artifacts: base, mode: .baseSetup)
    }

    func loadSessionSummaries() async -> [VMSessionSummary] {
        do {
            try paths.ensureDirectories()
        } catch {
            return []
        }

        var summaries: [VMSessionSummary] = [
            VMSessionSummary(id: "primary", name: "Primary", kind: .primary)
        ]

        let sessionsURL = paths.sessionsDirectoryURL
        if let contents = try? FileManager.default.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: nil) {
            for url in contents where url.pathExtension == "vm" {
                let id = url.deletingPathExtension().lastPathComponent
                if id == "primary" {
                    continue
                }
                let artifacts = VMArtifacts(bundleURL: url)
                if let data = try? Data(contentsOf: artifacts.metadataURL),
                   let summary = try? JSONDecoder().decode(VMSessionSummary.self, from: data) {
                    summaries.append(summary)
                } else {
                    summaries.append(VMSessionSummary(id: id, name: id, kind: .disposable))
                }
            }
        }

        return summaries
    }

    func prepareSessionInstance(
        kind: SessionKind,
        log: @escaping (String) -> Void,
        progress: @escaping (String) -> Void
    ) async throws -> VMInstance {
        try paths.ensureDirectories()

        let baseArtifacts = VMArtifacts(bundleURL: paths.baseBundleURL)
        if !baseArtifacts.exists() {
            log("Base VM missing. Preparing restore image.")
            progress("Downloading IPSW")
            try await downloader.downloadLatestIfNeeded(to: paths.restoreImageURL) { fraction in
                log("IPSW download progress: \(Int(fraction * 100))%")
            }

            progress("Installing macOS")
            log("Installing base VM. This can take a while.")
            let installer = VMInstaller(sizing: sizing, displaySize: displaySize)
            try await installer.installBase(
                restoreImageURL: paths.restoreImageURL,
                artifacts: baseArtifacts,
                diskSizeGB: UInt64(sizing.diskSizeGB)
            ) { fraction in
                log("Install progress: \(Int(fraction * 100))%")
            }
            log("Base VM installed. Complete macOS setup inside the VM once it boots.")
        }

        if !isBaseReady(baseArtifacts) {
            progress("Base setup required")
            log("Booting base VM for first-time setup.")
            let instance = try await buildInstance(sessionID: "base-setup", artifacts: baseArtifacts, mode: .baseSetup)
            progress("Starting base VM")
            return instance
        }

        let session = try prepareSession(kind: kind, baseArtifacts: baseArtifacts, log: log)
        let instance = try await buildInstance(sessionID: session.id, artifacts: session.artifacts, mode: .session(kind))

        progress("Starting VM")
        log("Starting VM session: \(session.id)")
        return instance
    }

    func startSessionByID(_ sessionID: String, kind: SessionKind) async throws -> VMInstance {
        let instance = try await buildSessionInstance(sessionID, kind: kind)
        try await instance.start()
        return instance
    }

    func buildSessionInstance(_ sessionID: String, kind: SessionKind) async throws -> VMInstance {
        try paths.ensureDirectories()
        let baseArtifacts = VMArtifacts(bundleURL: paths.baseBundleURL)
        guard baseArtifacts.exists() else {
            throw VMError.baseNotReady
        }

        let sessionArtifacts = try ensureSessionArtifacts(sessionID: sessionID, kind: kind, baseArtifacts: baseArtifacts)
        return try await buildInstance(sessionID: sessionID, artifacts: sessionArtifacts, mode: .session(kind))
    }

    private func ensureSessionArtifacts(
        sessionID: String,
        kind: SessionKind,
        baseArtifacts: VMArtifacts
    ) throws -> VMArtifacts {
        let sessionArtifacts = VMArtifacts(bundleURL: paths.sessionBundleURL(id: sessionID))
        if sessionArtifacts.exists() {
            return sessionArtifacts
        }
        if kind == .primary {
            _ = try prepareSession(kind: .primary, baseArtifacts: baseArtifacts) { _ in }
            return VMArtifacts(bundleURL: paths.sessionBundleURL(id: sessionID))
        }
        throw VMError.sessionNotFound(sessionID)
    }

    private func prepareSession(
        kind: SessionKind,
        baseArtifacts: VMArtifacts,
        log: @escaping (String) -> Void
    ) throws -> (id: String, artifacts: VMArtifacts) {
        let sessionID: String
        switch kind {
        case .primary:
            sessionID = "primary"
        case .disposable:
            sessionID = "session-\(UUID().uuidString.lowercased())"
        }

        let sessionURL = paths.sessionBundleURL(id: sessionID)
        let sessionArtifacts = VMArtifacts(bundleURL: sessionURL)
        if sessionArtifacts.exists() {
            return (sessionID, sessionArtifacts)
        }

        log("Creating session bundle: \(sessionID)")
        let summary = try createSessionBundle(
            sessionID: sessionID,
            name: kind == .primary ? "Primary" : sessionID,
            kind: kind,
            sourceArtifacts: baseArtifacts,
            overwrite: false
        )
        return (summary.id, VMArtifacts(bundleURL: paths.sessionBundleURL(id: summary.id)))
    }

    private func buildInstance(sessionID: String, artifacts: VMArtifacts, mode: VMRunMode) async throws -> VMInstance {
        AppLog.info("Building VM instance '\(sessionID)' with \(sizing.cpuCount) CPUs, \(sizing.memorySize / 1024 / 1024 / 1024)GB RAM.")
        let preflight = RuntimeDiagnostics.virtualizationPreflight()
        RuntimeDiagnostics.logVirtualizationPreflight(preflight, context: "buildInstance")
        if !preflight.missingEntitlements.isEmpty {
            throw VMError.missingEntitlement(preflight.missingEntitlements.joined(separator: ", "))
        }
        try assertArtifactsExist(artifacts)
        logArtifactDetails(artifacts)

        let hardwareModel = try VMConfigurationBuilder.loadHardwareModel(from: artifacts.hardwareModelURL)
        let machineIdentifier = try VMConfigurationBuilder.loadMachineIdentifier(from: artifacts.machineIdentifierURL)
        AppLog.info("Hardware model supported: \(hardwareModel.isSupported)")
        AppLog.info("Loading auxiliary storage from \(artifacts.auxiliaryStorageURL.path).")
        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: artifacts.auxiliaryStorageURL)

        AppLog.info("Creating VM configuration.")
        let builder = VMConfigurationBuilder(sizing: sizing, displaySize: displaySize)
        let configuration = try builder.makeConfiguration(
            artifacts: artifacts,
            hardwareModel: hardwareModel,
            machineIdentifier: machineIdentifier,
            auxiliaryStorage: auxiliaryStorage
        )
        AppLog.info("Configuration validated. Boot loader: \(type(of: configuration.bootLoader))")
        AppLog.info("Instantiating VZVirtualMachine.")
        let virtualMachine = VZVirtualMachine(configuration: configuration)
        return VMInstance(id: sessionID, virtualMachine: virtualMachine, mode: mode)
    }

    private func assertArtifactsExist(_ artifacts: VMArtifacts) throws {
        let fileManager = FileManager.default
        let checks = [
            ("disk image", artifacts.diskImageURL),
            ("auxiliary storage", artifacts.auxiliaryStorageURL),
            ("hardware model", artifacts.hardwareModelURL),
            ("machine identifier", artifacts.machineIdentifierURL),
        ]

        for (label, url) in checks {
            if !fileManager.fileExists(atPath: url.path) {
                AppLog.error("Missing \(label) at \(url.path).")
                throw VMError.missingArtifact("\(label) at \(url.path)")
            }
        }
    }

    private func logArtifactDetails(_ artifacts: VMArtifacts) {
        logFileInfo(label: "Disk image", url: artifacts.diskImageURL)
        logFileInfo(label: "Auxiliary storage", url: artifacts.auxiliaryStorageURL)
        logFileInfo(label: "Hardware model", url: artifacts.hardwareModelURL)
        logFileInfo(label: "Machine identifier", url: artifacts.machineIdentifierURL)
    }

    private func logFileInfo(label: String, url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            AppLog.error("\(label) missing at \(url.path).")
            return
        }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                AppLog.info("\(label) size: \(size.intValue) bytes (\(formatBytes(size.uint64Value)))")
            } else {
                AppLog.info("\(label) size: unknown (\(url.path))")
            }
        } catch {
            AppLog.error("Failed to read \(label) attributes: \(error.localizedDescription)")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        if gb >= 1 {
            return String(format: "%.2fGB", gb)
        }
        let mb = Double(bytes) / 1024.0 / 1024.0
        return String(format: "%.2fMB", mb)
    }

    func cloneDiskImage(from sourceURL: URL, to destinationURL: URL) throws {
        let result = copyfile(sourceURL.path, destinationURL.path, nil, copyfile_flags_t(COPYFILE_CLONE))
        if result != 0 {
            throw VMError.invalidDiskImage
        }
    }

    private func cloneFile(from sourceURL: URL, to destinationURL: URL, label: String) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let result = copyfile(sourceURL.path, destinationURL.path, nil, copyfile_flags_t(COPYFILE_CLONE))
        if result != 0 {
            throw VMError.copyFailed(label)
        }
    }

    func createPrimaryFromBase() throws {
        let base = baseArtifacts()
        guard base.exists() else {
            throw VMError.baseNotReady
        }
        _ = try createSessionBundle(
            sessionID: "primary",
            name: "Primary",
            kind: .primary,
            sourceArtifacts: base,
            overwrite: true
        )
    }

    func cloneSession(name: String, source: SessionCloneSource, selectedSessionID: String?) throws -> VMSessionSummary {
        try paths.ensureDirectories()

        let sourceArtifacts: VMArtifacts
        switch source {
        case .base:
            let base = baseArtifacts()
            guard base.exists() else {
                throw VMError.baseNotReady
            }
            sourceArtifacts = base
        case .primary:
            let primary = sessionArtifacts(id: "primary")
            guard primary.exists() else {
                throw VMError.sessionNotFound("primary")
            }
            sourceArtifacts = primary
        case .selected:
            guard let selectedSessionID else {
                throw VMError.sessionNotFound("selected")
            }
            let selected = sessionArtifacts(id: selectedSessionID)
            guard selected.exists() else {
                throw VMError.sessionNotFound(selectedSessionID)
            }
            sourceArtifacts = selected
        }

        let sessionID = "session-\(UUID().uuidString.lowercased())"
        return try createSessionBundle(
            sessionID: sessionID,
            name: name,
            kind: .disposable,
            sourceArtifacts: sourceArtifacts,
            overwrite: false
        )
    }

    @discardableResult
    private func createSessionBundle(
        sessionID: String,
        name: String,
        kind: SessionKind,
        sourceArtifacts: VMArtifacts,
        overwrite: Bool
    ) throws -> VMSessionSummary {
        let sessionArtifacts = VMArtifacts(bundleURL: paths.sessionBundleURL(id: sessionID))
        if sessionArtifacts.exists() {
            if overwrite {
                try FileManager.default.removeItem(at: sessionArtifacts.bundleURL)
            } else {
                let summary = VMSessionSummary(id: sessionID, name: name, kind: kind)
                return summary
            }
        }

        try FileManager.default.createDirectory(at: sessionArtifacts.bundleURL, withIntermediateDirectories: true)
        try cloneDiskImage(from: sourceArtifacts.diskImageURL, to: sessionArtifacts.diskImageURL)
        try cloneFile(from: sourceArtifacts.auxiliaryStorageURL, to: sessionArtifacts.auxiliaryStorageURL, label: "auxiliary storage")
        try cloneFile(from: sourceArtifacts.hardwareModelURL, to: sessionArtifacts.hardwareModelURL, label: "hardware model")
        try cloneFile(from: sourceArtifacts.machineIdentifierURL, to: sessionArtifacts.machineIdentifierURL, label: "machine identifier")

        let summary = VMSessionSummary(id: sessionID, name: name, kind: kind)
        try writeSessionMetadata(summary, to: sessionArtifacts.metadataURL)
        return summary
    }

    private func writeSessionMetadata(_ summary: VMSessionSummary, to url: URL) throws {
        let data = try JSONEncoder().encode(summary)
        try data.write(to: url)
    }

    func markBaseReady() throws {
        let baseArtifacts = VMArtifacts(bundleURL: paths.baseBundleURL)
        FileManager.default.createFile(atPath: baseArtifacts.baseReadyURL.path, contents: Data("ready".utf8))
    }

    func isBaseReady(_ artifacts: VMArtifacts) -> Bool {
        FileManager.default.fileExists(atPath: artifacts.baseReadyURL.path)
    }

    func deleteSession(id: String) throws {
        let url = paths.sessionBundleURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func loadCheckpoints(sessionID: String) -> [VMCheckpoint] {
        let directory = paths.checkpointsDirectoryURL(sessionID: sessionID)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path),
              let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        var checkpoints: [VMCheckpoint] = []
        for url in contents {
            let metadataURL = url.appendingPathComponent("Checkpoint.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let checkpoint = try? JSONDecoder().decode(VMCheckpoint.self, from: data) else {
                continue
            }
            checkpoints.append(checkpoint)
        }

        return checkpoints.sorted { $0.createdAt > $1.createdAt }
    }

    func checkpointPaths(sessionID: String, checkpointID: String) -> (bundle: URL, disk: URL, state: URL, metadata: URL) {
        (
            bundle: paths.checkpointBundleURL(sessionID: sessionID, checkpointID: checkpointID),
            disk: paths.checkpointDiskImageURL(sessionID: sessionID, checkpointID: checkpointID),
            state: paths.checkpointStateURL(sessionID: sessionID, checkpointID: checkpointID),
            metadata: paths.checkpointMetadataURL(sessionID: sessionID, checkpointID: checkpointID)
        )
    }

    func writeCheckpointMetadata(_ checkpoint: VMCheckpoint) throws {
        let metadataURL = paths.checkpointMetadataURL(sessionID: checkpoint.sessionID, checkpointID: checkpoint.id)
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: metadataURL)
    }

    func deleteCheckpoint(sessionID: String, checkpointID: String) throws {
        let url = paths.checkpointBundleURL(sessionID: sessionID, checkpointID: checkpointID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func openCheckpointsFolder(sessionID: String) {
        let url = paths.checkpointsDirectoryURL(sessionID: sessionID)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }

    func deleteBase() throws {
        let base = baseArtifacts()
        if base.exists() {
            try FileManager.default.removeItem(at: base.bundleURL)
        }
    }

    func refreshRestoreImageCatalog() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            VZMacOSRestoreImage.fetchLatestSupported { result in
                switch result {
                case .success:
                    continuation.resume(returning: .success(()))
                case .failure(let error):
                    AppLog.error("Restore image catalog refresh failed: \(error.localizedDescription) (\(ErrorDiagnostics.describe(error)))")
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
}
