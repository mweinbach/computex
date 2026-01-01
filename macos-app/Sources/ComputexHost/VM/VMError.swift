import Foundation

enum VMError: LocalizedError {
    case missingRestoreImage
    case restoreImageDownloadFailed(String)
    case restoreImageUnsupported
    case invalidHardwareModel
    case invalidMachineIdentifier
    case invalidDiskImage
    case installationFailed(String)
    case configurationFailed(String)
    case startFailed(String)
    case stopFailed(String)
    case baseNotReady
    case missingArtifact(String)

    var errorDescription: String? {
        switch self {
        case .missingRestoreImage:
            return "Missing restore image"
        case .restoreImageDownloadFailed(let message):
            return "Restore image download failed: \(message)"
        case .restoreImageUnsupported:
            return "Restore image is not supported on this host"
        case .invalidHardwareModel:
            return "Hardware model is invalid"
        case .invalidMachineIdentifier:
            return "Machine identifier is invalid"
        case .invalidDiskImage:
            return "Disk image is invalid"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .configurationFailed(let message):
            return "Configuration failed: \(message)"
        case .startFailed(let message):
            return "VM start failed: \(message)"
        case .stopFailed(let message):
            return "VM stop failed: \(message)"
        case .baseNotReady:
            return "Base VM is not ready"
        case .missingArtifact(let message):
            return "Missing VM artifact: \(message)"
        }
    }
}
