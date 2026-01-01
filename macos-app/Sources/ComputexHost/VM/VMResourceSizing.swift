import Foundation
import Virtualization

struct VMResourceSizing {
    let cpuCount: Int
    let memorySize: UInt64
    let diskSizeGB: Int

    static func `default`() -> VMResourceSizing {
        let cpu = clamp(
            value: 2,
            min: VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            max: VZVirtualMachineConfiguration.maximumAllowedCPUCount
        )
        let memory = clamp(
            value: 4 * 1024 * 1024 * 1024,
            min: VZVirtualMachineConfiguration.minimumAllowedMemorySize,
            max: VZVirtualMachineConfiguration.maximumAllowedMemorySize
        )
        return VMResourceSizing(cpuCount: cpu, memorySize: memory, diskSizeGB: 64)
    }

    static func fromPreferences(_ prefs: VMPrefs) -> VMResourceSizing {
        let cpu = clamp(
            value: prefs.cpuCount,
            min: VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            max: VZVirtualMachineConfiguration.maximumAllowedCPUCount
        )
        let memory = clamp(
            value: UInt64(prefs.memoryGB) * 1024 * 1024 * 1024,
            min: VZVirtualMachineConfiguration.minimumAllowedMemorySize,
            max: VZVirtualMachineConfiguration.maximumAllowedMemorySize
        )
        let diskSizeGB = max(32, prefs.diskGB)
        return VMResourceSizing(cpuCount: cpu, memorySize: memory, diskSizeGB: diskSizeGB)
    }

    private static func clamp<T: Comparable>(value: T, min: T, max: T) -> T {
        Swift.max(min, Swift.min(max, value))
    }
}
