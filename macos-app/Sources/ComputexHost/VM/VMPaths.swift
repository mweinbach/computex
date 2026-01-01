import Foundation

struct VMPaths {
    let root: URL

    static func defaultRoot() -> VMPaths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("Computex", isDirectory: true)
            .appendingPathComponent("VMs", isDirectory: true)
        return VMPaths(root: root)
    }

    var restoreImageURL: URL {
        root.appendingPathComponent("RestoreImage.ipsw")
    }

    var ipswDirectoryURL: URL {
        root.appendingPathComponent("IPSWs", isDirectory: true)
    }

    var settingsURL: URL {
        root.appendingPathComponent("Settings.json")
    }

    var baseBundleURL: URL {
        root.appendingPathComponent("Base.vm", isDirectory: true)
    }

    var sessionsDirectoryURL: URL {
        root.appendingPathComponent("Sessions", isDirectory: true)
    }

    func sessionBundleURL(id: String) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(id).vm", isDirectory: true)
    }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ipswDirectoryURL, withIntermediateDirectories: true)
    }
}
