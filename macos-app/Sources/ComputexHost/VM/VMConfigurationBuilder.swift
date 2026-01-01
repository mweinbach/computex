import CoreGraphics
import Foundation
import Virtualization

struct VMConfigurationBuilder {
    let sizing: VMResourceSizing
    let displaySize: CGSize

    func makeConfiguration(
        artifacts: VMArtifacts,
        hardwareModel: VZMacHardwareModel,
        machineIdentifier: VZMacMachineIdentifier,
        auxiliaryStorage: VZMacAuxiliaryStorage
    ) throws -> VZVirtualMachineConfiguration {
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = makePlatformConfiguration(
            hardwareModel: hardwareModel,
            machineIdentifier: machineIdentifier,
            auxiliaryStorage: auxiliaryStorage
        )
        configuration.cpuCount = sizing.cpuCount
        configuration.memorySize = sizing.memorySize
        configuration.bootLoader = VZMacOSBootLoader()
        configuration.graphicsDevices = [makeGraphicsDevice()]
        configuration.storageDevices = [try makeStorageDevice(diskImageURL: artifacts.diskImageURL)]
        configuration.networkDevices = [makeNetworkDevice()]
        configuration.pointingDevices = [VZMacTrackpadConfiguration()]
        configuration.keyboards = [VZMacKeyboardConfiguration()]
        configuration.audioDevices = [makeAudioDevice()]

        try configuration.validate()
        if #available(macOS 14.0, *) {
            try configuration.validateSaveRestoreSupport()
        }
        return configuration
    }

    private func makePlatformConfiguration(
        hardwareModel: VZMacHardwareModel,
        machineIdentifier: VZMacMachineIdentifier,
        auxiliaryStorage: VZMacAuxiliaryStorage
    ) -> VZMacPlatformConfiguration {
        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = hardwareModel
        platform.machineIdentifier = machineIdentifier
        platform.auxiliaryStorage = auxiliaryStorage
        return platform
    }

    private func makeGraphicsDevice() -> VZMacGraphicsDeviceConfiguration {
        let graphics = VZMacGraphicsDeviceConfiguration()
        let width = Int(displaySize.width)
        let height = Int(displaySize.height)
        graphics.displays = [VZMacGraphicsDisplayConfiguration(
            widthInPixels: width,
            heightInPixels: height,
            pixelsPerInch: 80
        )]
        return graphics
    }

    private func makeStorageDevice(diskImageURL: URL) throws -> VZVirtioBlockDeviceConfiguration {
        let attachment = try VZDiskImageStorageDeviceAttachment(url: diskImageURL, readOnly: false)
        return VZVirtioBlockDeviceConfiguration(attachment: attachment)
    }

    private func makeNetworkDevice() -> VZVirtioNetworkDeviceConfiguration {
        let device = VZVirtioNetworkDeviceConfiguration()
        device.attachment = VZNATNetworkDeviceAttachment()
        return device
    }

    private func makeAudioDevice() -> VZVirtioSoundDeviceConfiguration {
        let audio = VZVirtioSoundDeviceConfiguration()
        let input = VZVirtioSoundDeviceInputStreamConfiguration()
        input.source = VZHostAudioInputStreamSource()
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        audio.streams = [input, output]
        return audio
    }

    static func loadHardwareModel(from url: URL) throws -> VZMacHardwareModel {
        let data = try Data(contentsOf: url)
        guard let model = VZMacHardwareModel(dataRepresentation: data) else {
            throw VMError.invalidHardwareModel
        }
        return model
    }

    static func loadMachineIdentifier(from url: URL) throws -> VZMacMachineIdentifier {
        let data = try Data(contentsOf: url)
        guard let identifier = VZMacMachineIdentifier(dataRepresentation: data) else {
            throw VMError.invalidMachineIdentifier
        }
        return identifier
    }

    static func writeHardwareModel(_ model: VZMacHardwareModel, to url: URL) throws {
        try model.dataRepresentation.write(to: url)
    }

    static func writeMachineIdentifier(_ identifier: VZMacMachineIdentifier, to url: URL) throws {
        try identifier.dataRepresentation.write(to: url)
    }
}
