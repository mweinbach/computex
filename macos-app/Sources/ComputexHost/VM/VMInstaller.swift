import CoreGraphics
import Darwin
import Foundation
import Virtualization

@MainActor
final class VMInstaller {
    private let sizing: VMResourceSizing
    private let displaySize: CGSize

    init(sizing: VMResourceSizing, displaySize: CGSize) {
        self.sizing = sizing
        self.displaySize = displaySize
    }

    func installBase(
        restoreImageURL: URL,
        artifacts: VMArtifacts,
        diskSizeGB: UInt64,
        progress: @escaping (Double) -> Void
    ) async throws {
        let preflight = RuntimeDiagnostics.virtualizationPreflight()
        RuntimeDiagnostics.logVirtualizationPreflight(preflight, context: "installBase")
        if !preflight.missingEntitlements.isEmpty {
            throw VMError.missingEntitlement(preflight.missingEntitlements.joined(separator: ", "))
        }

        let restoreImage = try await loadRestoreImage(from: restoreImageURL)
        guard let requirements = restoreImage.mostFeaturefulSupportedConfiguration else {
            throw VMError.restoreImageUnsupported
        }
        if !requirements.hardwareModel.isSupported {
            throw VMError.restoreImageUnsupported
        }

        try FileManager.default.createDirectory(at: artifacts.bundleURL, withIntermediateDirectories: true)
        try createDiskImage(at: artifacts.diskImageURL, sizeInGB: diskSizeGB)

        let auxiliaryStorage = try VZMacAuxiliaryStorage(
            creatingStorageAt: artifacts.auxiliaryStorageURL,
            hardwareModel: requirements.hardwareModel,
            options: []
        )

        let machineIdentifier = VZMacMachineIdentifier()
        try VMConfigurationBuilder.writeHardwareModel(requirements.hardwareModel, to: artifacts.hardwareModelURL)
        try VMConfigurationBuilder.writeMachineIdentifier(machineIdentifier, to: artifacts.machineIdentifierURL)

        let builder = VMConfigurationBuilder(sizing: sizing, displaySize: displaySize)
        let configuration = try builder.makeConfiguration(
            artifacts: artifacts,
            hardwareModel: requirements.hardwareModel,
            machineIdentifier: machineIdentifier,
            auxiliaryStorage: auxiliaryStorage
        )

        let virtualMachine = VZVirtualMachine(configuration: configuration)
        let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: restoreImageURL)
        let observer = installer.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progressValue, _ in
            progress(progressValue.fractionCompleted)
        }

        defer { observer.invalidate() }

        try await withCheckedThrowingContinuation { continuation in
            installer.install { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: VMError.installationFailed(error.localizedDescription))
                }
            }
        }
    }

    private func loadRestoreImage(from url: URL) async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { continuation in
            VZMacOSRestoreImage.load(from: url) { result in
                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure(let error):
                    continuation.resume(throwing: VMError.restoreImageDownloadFailed(error.localizedDescription))
                }
            }
        }
    }

    private func createDiskImage(at url: URL, sizeInGB: UInt64) throws {
        let sizeInBytes = sizeInGB * 1024 * 1024 * 1024
        let fd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        if fd == -1 {
            throw VMError.invalidDiskImage
        }
        defer { close(fd) }
        if ftruncate(fd, off_t(sizeInBytes)) != 0 {
            throw VMError.invalidDiskImage
        }
    }
}
