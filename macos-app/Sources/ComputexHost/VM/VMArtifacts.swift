import Foundation

struct VMArtifacts {
    let bundleURL: URL

    var diskImageURL: URL {
        bundleURL.appendingPathComponent("Disk.img")
    }

    var auxiliaryStorageURL: URL {
        bundleURL.appendingPathComponent("AuxiliaryStorage")
    }

    var hardwareModelURL: URL {
        bundleURL.appendingPathComponent("HardwareModel")
    }

    var machineIdentifierURL: URL {
        bundleURL.appendingPathComponent("MachineIdentifier")
    }

    var metadataURL: URL {
        bundleURL.appendingPathComponent("Session.json")
    }

    var baseReadyURL: URL {
        bundleURL.appendingPathComponent("BaseReady")
    }

    func exists() -> Bool {
        FileManager.default.fileExists(atPath: bundleURL.path)
    }
}
