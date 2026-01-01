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

    func startBaseSetup() async throws -> VMInstance {
        try paths.ensureDirectories()
        let base = baseArtifacts()
        guard base.exists() else {
            AppLog.error("Base VM not found at \(base.bundleURL.path).")
            throw VMError.baseNotReady
        }
        AppLog.info("Starting base setup VM.")
        let instance = try await buildInstance(sessionID: "base-setup", artifacts: base, mode: .baseSetup)
        try await instance.start()
        return instance
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

    func startSession(
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
            try await instance.start()
            return instance
        }

        let session = try prepareSession(kind: kind, baseArtifacts: baseArtifacts, log: log)
        let instance = try await buildInstance(sessionID: session.id, artifacts: session.artifacts, mode: .session(kind))

        progress("Starting VM")
        log("Starting VM session: \(session.id)")
        try await instance.start()
        return instance
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
        try FileManager.default.createDirectory(at: sessionArtifacts.bundleURL, withIntermediateDirectories: true)
        try cloneDiskImage(from: baseArtifacts.diskImageURL, to: sessionArtifacts.diskImageURL)

        let hardwareModel = try VMConfigurationBuilder.loadHardwareModel(from: baseArtifacts.hardwareModelURL)
        let machineIdentifier = VZMacMachineIdentifier()
        _ = try VZMacAuxiliaryStorage(
            creatingStorageAt: sessionArtifacts.auxiliaryStorageURL,
            hardwareModel: hardwareModel,
            options: []
        )

        try VMConfigurationBuilder.writeHardwareModel(hardwareModel, to: sessionArtifacts.hardwareModelURL)
        try VMConfigurationBuilder.writeMachineIdentifier(machineIdentifier, to: sessionArtifacts.machineIdentifierURL)

        let name = kind == .primary ? "Primary" : sessionID
        let summary = VMSessionSummary(id: sessionID, name: name, kind: kind)
        try writeSessionMetadata(summary, to: sessionArtifacts.metadataURL)
        return (sessionID, sessionArtifacts)
    }

    private func buildInstance(sessionID: String, artifacts: VMArtifacts, mode: VMRunMode) async throws -> VMInstance {
        AppLog.info("Building VM instance '\(sessionID)' with \(sizing.cpuCount) CPUs, \(sizing.memorySize / 1024 / 1024 / 1024)GB RAM.")
        try assertArtifactsExist(artifacts)

        let hardwareModel = try VMConfigurationBuilder.loadHardwareModel(from: artifacts.hardwareModelURL)
        let machineIdentifier = try VMConfigurationBuilder.loadMachineIdentifier(from: artifacts.machineIdentifierURL)
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

    private func cloneDiskImage(from sourceURL: URL, to destinationURL: URL) throws {
        let result = copyfile(sourceURL.path, destinationURL.path, nil, copyfile_flags_t(COPYFILE_CLONE))
        if result != 0 {
            throw VMError.invalidDiskImage
        }
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
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
}
