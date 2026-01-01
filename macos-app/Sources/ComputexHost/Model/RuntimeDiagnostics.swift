import Foundation
import Security
import Virtualization

enum RuntimeDiagnostics {
    static func logEnvironment() {
        let bundleURL = Bundle.main.bundleURL
        let processInfo = ProcessInfo.processInfo
        AppLog.info("Bundle URL: \(bundleURL.path)")
        AppLog.info("Bundle path: \(Bundle.main.bundlePath)")
        if let executableURL = Bundle.main.executableURL {
            AppLog.info("Executable URL: \(executableURL.path)")
        }
        AppLog.info("Process ID: \(processInfo.processIdentifier)")
        AppLog.info("OS version: \(processInfo.operatingSystemVersionString)")
        AppLog.info("App bundle: \(bundleURL.pathExtension == "app")")
        AppLog.info("CPU allowed: \(VZVirtualMachineConfiguration.minimumAllowedCPUCount)-\(VZVirtualMachineConfiguration.maximumAllowedCPUCount)")
        AppLog.info("Memory allowed: \(formatBytes(VZVirtualMachineConfiguration.minimumAllowedMemorySize))-\(formatBytes(VZVirtualMachineConfiguration.maximumAllowedMemorySize))")

        logEntitlement("com.apple.security.virtualization")
        logEntitlement("com.apple.security.hypervisor")
        logEntitlement("com.apple.security.device.audio-input")
        logEntitlement("com.apple.security.app-sandbox")

        logUsageDescription("NSMicrophoneUsageDescription")
    }

    static func virtualizationPreflight() -> VirtualizationPreflight {
        let requiredEntitlements = ["com.apple.security.virtualization"]
        let missing = requiredEntitlements.filter { !hasEntitlement($0) }
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        let hasMicrophoneUsage = hasUsageDescription("NSMicrophoneUsageDescription")
        return VirtualizationPreflight(
            isAppBundle: isAppBundle,
            missingEntitlements: missing,
            hasMicrophoneUsageDescription: hasMicrophoneUsage
        )
    }

    static func logVirtualizationPreflight(_ preflight: VirtualizationPreflight, context: String) {
        AppLog.info("Virtualization preflight (\(context)):")
        AppLog.info("  app bundle: \(preflight.isAppBundle)")
        if preflight.missingEntitlements.isEmpty {
            AppLog.info("  entitlements: ok")
        } else {
            AppLog.error("  missing entitlements: \(preflight.missingEntitlements.joined(separator: ", "))")
        }
        AppLog.info("  microphone usage description: \(preflight.hasMicrophoneUsageDescription)")
    }

    static func hasEntitlement(_ key: String) -> Bool {
        entitlementValue(key) != nil
    }

    static func hasUsageDescription(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) as? String != nil
    }

    private static func logEntitlement(_ key: String) {
        guard let value = entitlementValue(key) else {
            AppLog.error("Entitlement \(key): missing")
            return
        }
        AppLog.info("Entitlement \(key): \(value)")
    }

    private static func entitlementValue(_ key: String) -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else {
            AppLog.error("Unable to create SecTask for entitlement check.")
            return nil
        }
        guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else {
            return nil
        }
        return String(describing: value)
    }

    private static func logUsageDescription(_ key: String) {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            AppLog.info("\(key): \(value)")
        } else {
            AppLog.error("\(key): missing")
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        return String(format: "%.2fGB", gb)
    }
}

struct VirtualizationPreflight {
    let isAppBundle: Bool
    let missingEntitlements: [String]
    let hasMicrophoneUsageDescription: Bool
}
